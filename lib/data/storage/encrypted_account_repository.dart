import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/totp_account.dart';

abstract interface class AccountRepository {
  Future<List<TotpAccount>> loadAccounts();

  Future<void> saveAccounts(List<TotpAccount> accounts);

  Future<void> rotateEncryptionKey();
}

/// Narrow key-store interface so the encrypted repository can be tested
/// without a device Keystore.
abstract interface class DeviceKeyStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterDeviceKeyStore implements DeviceKeyStore {
  FlutterDeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: false),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LocalAccountDataException implements Exception {
  const LocalAccountDataException(this.message);

  final String message;

  @override
  String toString() => 'LocalAccountDataException: $message';
}

class LocalEncryptionKeyUnavailableException extends LocalAccountDataException {
  const LocalEncryptionKeyUnavailableException()
      : super('This device encryption key is unavailable. The saved data was preserved. Restore from an encrypted backup when available.');
}

/// Stores the complete account collection as one AES-256-GCM authenticated
/// blob in app-private storage. The random data-encryption key is stored through
/// Android Keystore-backed flutter_secure_storage and is never written beside
/// the encrypted file.
class EncryptedAccountRepository implements AccountRepository {
  EncryptedAccountRepository({
    required DeviceKeyStore keyStore,
    Future<Directory> Function()? supportDirectoryProvider,
    Random? secureRandom,
  })  : _keyStore = keyStore,
        _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory,
        _random = secureRandom ?? Random.secure();

  static const _envelopeVersion = 1;
  static const _payloadVersion = 1;
  static const _keyNamePrefix = 'tinyotp.data-key.v1.';
  static const _aadPrefix = 'TinyOTP/local-account-store/v1/';
  static const _fileName = 'accounts.v1.enc.json';
  static final _cipher = AesGcm.with256bits();

  final DeviceKeyStore _keyStore;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Random _random;
  Future<void> _serialTail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _serialTail;
    final next = Completer<void>();
    _serialTail = next.future;
    await previous;
    try {
      return await operation();
    } finally {
      next.complete();
    }
  }

  Future<File> _accountFile() async {
    final directory = await _supportDirectoryProvider();
    final child = Directory('${directory.path}${Platform.pathSeparator}tinyotp');
    await child.create(recursive: true);
    return File('${child.path}${Platform.pathSeparator}$_fileName');
  }

  File _backupFile(File file) => File('${file.path}.bak');

  @override
  Future<List<TotpAccount>> loadAccounts() => _serialized(_loadAccounts);

  Future<List<TotpAccount>> _loadAccounts() async {
    final file = await _accountFile();
    final source = await _readableFile(file);
    if (source == null) return const [];
    final envelope = await _readEnvelope(source);
    final keyBytes = await _readRequiredKey(envelope.keyId);
    final payload = await _decrypt(envelope, keyBytes);
    if (!await file.exists()) {
      // A crash may have occurred after preserving the previous complete file
      // but before installing its replacement.
      await source.rename(file.path);
    } else if (source.path != file.path) {
      await source.delete();
    }
    return payload;
  }

  @override
  Future<void> saveAccounts(List<TotpAccount> accounts) =>
      _serialized(() => _saveAccounts(accounts));

  Future<void> _saveAccounts(List<TotpAccount> accounts) async {
    _validateAccounts(accounts);
    final file = await _accountFile();
    final currentFile = await _readableFile(file);
    late final String keyId;
    late final List<int> keyBytes;

    if (currentFile != null) {
      // Fail closed if an existing record cannot be decrypted. A caller must
      // never replace unreadable account data with an apparently empty list.
      final current = await _readEnvelope(currentFile);
      keyId = current.keyId;
      keyBytes = await _readRequiredKey(keyId);
      await _decrypt(current, keyBytes);
    } else {
      final created = await _createKey();
      keyId = created.$1;
      keyBytes = created.$2;
    }

    final envelope = await _encrypt(accounts, keyId, keyBytes);
    await _commit(file, envelope);
  }

  @override
  Future<void> rotateEncryptionKey() => _serialized(_rotateEncryptionKey);

  Future<void> _rotateEncryptionKey() async {
    final file = await _accountFile();
    final source = await _readableFile(file);
    if (source == null) return;
    final currentEnvelope = await _readEnvelope(source);
    final currentKey = await _readRequiredKey(currentEnvelope.keyId);
    final accounts = await _decrypt(currentEnvelope, currentKey);
    // Store the new key first. The envelope identifies its key, so a crash
    // before commit leaves the old file/key usable; a crash after commit leaves
    // the new key usable. The old key is deleted only after the new file lands.
    final (newKeyId, newKey) = await _createKey();
    final nextEnvelope = await _encrypt(accounts, newKeyId, newKey);
    await _commit(file, nextEnvelope);
    if (newKeyId != currentEnvelope.keyId) {
      try {
        await _keyStore.delete(_keyName(currentEnvelope.keyId));
      } on Object {
        throw const LocalAccountDataException(
          'The data key was rotated, but the retired key could not be removed. The accounts remain protected.',
        );
      }
    }
  }

  Future<File?> _readableFile(File file) async {
    if (await file.exists()) return file;
    final backup = _backupFile(file);
    if (await backup.exists()) return backup;
    return null;
  }

  Future<_Envelope> _readEnvelope(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _envelopeVersion ||
          decoded['keyId'] is! String ||
          decoded['nonce'] is! String ||
          decoded['cipherText'] is! String ||
          decoded['mac'] is! String) {
        throw const FormatException('Invalid encrypted envelope.');
      }
      final keyId = decoded['keyId'] as String;
      if (!RegExp(r'^[A-Za-z0-9_-]{20,32}$').hasMatch(keyId)) {
        throw const FormatException('Invalid encryption key identifier.');
      }
      final nonce = _decodeBase64(decoded['nonce'] as String);
      final cipherText = _decodeBase64(decoded['cipherText'] as String);
      final mac = _decodeBase64(decoded['mac'] as String);
      if (nonce.length != _cipher.nonceLength || mac.length != _cipher.macAlgorithm.macLength) {
        throw const FormatException('Invalid authenticated encryption fields.');
      }
      return _Envelope(keyId: keyId, nonce: nonce, cipherText: cipherText, mac: mac);
    } on LocalAccountDataException {
      rethrow;
    } on Object {
      throw const LocalAccountDataException(
        'The encrypted account file is damaged or uses an unsupported format. No data was changed.',
      );
    }
  }

  Future<List<int>> _readRequiredKey(String keyId) async {
    String? stored;
    try {
      stored = await _keyStore.read(_keyName(keyId));
    } on Object {
      throw const LocalEncryptionKeyUnavailableException();
    }
    if (stored == null) throw const LocalEncryptionKeyUnavailableException();
    try {
      final bytes = _decodeBase64(stored);
      if (bytes.length != 32) throw const FormatException('Unexpected key length.');
      return bytes;
    } on Object {
      throw const LocalEncryptionKeyUnavailableException();
    }
  }

  Future<void> _writeNewKey(String keyId, List<int> keyBytes) async {
    final name = _keyName(keyId);
    try {
      await _keyStore.write(name, base64Url.encode(keyBytes));
      final saved = await _keyStore.read(name);
      if (saved == null || !_constantTimeEqual(_decodeBase64(saved), keyBytes)) {
        throw const LocalAccountDataException('The device could not safely retain the encryption key.');
      }
    } on LocalAccountDataException {
      rethrow;
    } on Object {
      throw const LocalAccountDataException('Secure key storage is unavailable. No account data was changed.');
    }
  }

  Future<(String, List<int>)> _createKey() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final keyId = _newKeyId();
      String? existing;
      try {
        existing = await _keyStore.read(_keyName(keyId));
      } on Object {
        throw const LocalAccountDataException('Secure key storage is unavailable. No account data was changed.');
      }
      if (existing != null) continue;
      final keyBytes = List<int>.unmodifiable(List<int>.generate(32, (_) => _random.nextInt(256)));
      await _writeNewKey(keyId, keyBytes);
      return (keyId, keyBytes);
    }
    throw const LocalAccountDataException('A unique local encryption key could not be created.');
  }

  Future<List<TotpAccount>> _decrypt(_Envelope envelope, List<int> keyBytes) async {
    try {
      final box = SecretBox(
        envelope.cipherText,
        nonce: envelope.nonce,
        mac: Mac(envelope.mac),
      );
      final clearText = await _cipher.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode('$_aadPrefix${envelope.keyId}'),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map<String, dynamic> ||
          decoded['formatVersion'] != _payloadVersion ||
          decoded['accounts'] is! List) {
        throw const FormatException('Invalid account payload.');
      }
      final accounts = (decoded['accounts'] as List).map((value) {
        if (value is! Map<String, dynamic>) throw const FormatException('Invalid account record.');
        return TotpAccount.fromJson(value);
      }).toList(growable: false);
      _validateAccounts(accounts);
      return List<TotpAccount>.unmodifiable(accounts);
    } on LocalAccountDataException {
      rethrow;
    } on Object {
      throw const LocalAccountDataException(
        'The account data could not be authenticated or decoded. The encrypted file was preserved.',
      );
    }
  }

  Future<_Envelope> _encrypt(List<TotpAccount> accounts, String keyId, List<int> keyBytes) async {
    final clearText = utf8.encode(jsonEncode({
      'formatVersion': _payloadVersion,
      'accounts': accounts.map(_serializeAccount).toList(growable: false),
    }));
    final box = await _cipher.encrypt(
      clearText,
      secretKey: SecretKey(keyBytes),
      aad: utf8.encode('$_aadPrefix$keyId'),
    );
    return _Envelope(keyId: keyId, nonce: box.nonce, cipherText: box.cipherText, mac: box.mac.bytes);
  }

  Future<void> _commit(File file, _Envelope envelope) async {
    final backup = _backupFile(file);
    final temporary = File('${file.path}.tmp');
    final serialized = jsonEncode({
      'version': _envelopeVersion,
      'keyId': envelope.keyId,
      'nonce': base64Url.encode(envelope.nonce),
      'cipherText': base64Url.encode(envelope.cipherText),
      'mac': base64Url.encode(envelope.mac),
    });
    try {
      await temporary.writeAsString(serialized, flush: true);
      if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      try {
        await temporary.rename(file.path);
      } on Object {
        if (!await file.exists() && await backup.exists()) {
          await backup.rename(file.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
    } on LocalAccountDataException {
      rethrow;
    } on Object {
      throw const LocalAccountDataException(
        'The encrypted account file could not be saved. Existing data was preserved where possible.',
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _newKeyId() =>
      base64Url.encode(List<int>.generate(16, (_) => _random.nextInt(256))).replaceAll('=', '');

  String _keyName(String keyId) => '$_keyNamePrefix$keyId';

  Map<String, Object> _serializeAccount(TotpAccount account) => {
        'id': account.id,
        'issuer': account.issuer,
        'accountName': account.accountName,
        'secret': base64Url.encode(account.secret),
        'algorithm': account.algorithm.name,
        'digits': account.digits,
        'period': account.period,
      };

  static List<int> _decodeBase64(String value) => base64Url.decode(base64Url.normalize(value));

  static void _validateAccounts(List<TotpAccount> accounts) {
    final ids = <String>{};
    for (final account in accounts) {
      if (account.id.isEmpty ||
          account.issuer.trim().isEmpty ||
          account.accountName.trim().isEmpty ||
          account.secret.isEmpty ||
          (account.digits != 6 && account.digits != 8) ||
          account.period <= 0 ||
          !ids.add(account.id)) {
        throw const LocalAccountDataException('The account collection contains invalid or repeated records.');
      }
    }
  }

  static bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

class _Envelope {
  const _Envelope({required this.keyId, required this.nonce, required this.cipherText, required this.mac});

  final String keyId;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;
}
