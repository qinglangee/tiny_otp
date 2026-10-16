import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../models/totp_account.dart';
import '../../totp/totp_generator.dart';

/// Password-protected, portable backup format. No device-specific key is used.
class EncryptedBackupService {
  EncryptedBackupService({Random? secureRandom}) : _random = secureRandom ?? Random.secure();

  static const int _version = 1;
  static const int _iterations = 600000;
  static const int maxBackupBytes = 10 * 1024 * 1024;
  static const int _maxPasswordBytes = 4096;
  static const _format = 'TinyOTP encrypted backup';
  static const _kdf = 'PBKDF2-HMAC-SHA256';
  static const _cipherName = 'AES-256-GCM';
  static final _cipher = AesGcm.with256bits();

  final Random _random;

  Future<List<int>> createBackup({required List<TotpAccount> accounts, required String password}) async {
    _validatePassword(password);
    _validateAccounts(accounts);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final payload = utf8.encode(jsonEncode({
      'version': _version,
      'accounts': accounts.map(_accountToJson).toList(growable: false),
    }));
    final aad = _aad(salt);
    final box = await _cipher.encrypt(payload, secretKey: SecretKey(key), nonce: nonce, aad: aad);
    final envelope = jsonEncode({
      'format': _format,
      'version': _version,
      'kdf': _kdf,
      'iterations': _iterations,
      'salt': base64.encode(salt),
      'cipher': _cipherName,
      'nonce': base64.encode(nonce),
      'ciphertext': base64.encode(box.cipherText),
      'tag': base64.encode(box.mac.bytes),
    });
    final result = utf8.encode(envelope);
    if (result.length > maxBackupBytes) throw const BackupFormatException('The backup is too large.');
    return result;
  }

  Future<List<TotpAccount>> restoreBackup({required List<int> bytes, required String password}) async {
    _validatePassword(password);
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const BackupFormatException('The selected backup file is empty or too large.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _format || decoded['version'] != _version ||
          decoded['kdf'] != _kdf || decoded['iterations'] != _iterations ||
          decoded['cipher'] != _cipherName) {
        throw const BackupFormatException('This backup format or version is not supported.');
      }
      final salt = _decodeBase64(decoded['salt'], expectedLength: 16);
      final nonce = _decodeBase64(decoded['nonce'], expectedLength: 12);
      final ciphertext = _decodeBase64(decoded['ciphertext']);
      final tag = _decodeBase64(decoded['tag'], expectedLength: 16);
      final key = await _deriveKey(password, salt);
      late final List<int> cleartext;
      try {
        cleartext = await _cipher.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
          secretKey: SecretKey(key),
          aad: _aad(salt),
        );
      } on SecretBoxAuthenticationError {
        throw const BackupPasswordException();
      }
      final payload = jsonDecode(utf8.decode(cleartext));
      if (payload is! Map<String, dynamic> || payload['version'] != _version || payload['accounts'] is! List) {
        throw const BackupFormatException('The backup contents are invalid.');
      }
      final accounts = (payload['accounts'] as List).map((item) {
        if (item is! Map<String, dynamic>) throw const BackupFormatException('The backup contents are invalid.');
        return TotpAccount.fromJson(Map<String, Object?>.from(item));
      }).toList(growable: false);
      _validateAccounts(accounts);
      return accounts;
    } on BackupFormatException {
      rethrow;
    } on BackupPasswordException {
      rethrow;
    } on FormatException {
      throw const BackupFormatException('The backup file is damaged or has an invalid format.');
    } on Object {
      throw const BackupFormatException('The password is incorrect, or the backup file is damaged.');
    }
  }

  List<int> _randomBytes(int count) => List<int>.generate(count, (_) => _random.nextInt(256));

  static List<int> _aad(List<int> salt) => utf8.encode('$_format|$_version|$_kdf|$_iterations|$_cipherName|${base64.encode(salt)}');

  static Future<List<int>> _deriveKey(String password, List<int> salt) => Isolate.run(
        () async => (await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: _iterations,
          bits: 256,
        ).deriveKeyFromPassword(password: password, nonce: salt)).extractBytes(),
      );

  static Map<String, Object> _accountToJson(TotpAccount account) => {
        'id': account.id,
        'issuer': account.issuer,
        'accountName': account.accountName,
        'secret': base64Url.encode(account.secret),
        'algorithm': account.algorithm.name,
        'digits': account.digits,
        'period': account.period,
      };

  static List<int> _decodeBase64(Object? value, {int? expectedLength}) {
    if (value is! String || value.length > maxBackupBytes * 2) {
      throw const BackupFormatException('The backup file is damaged or has an invalid format.');
    }
    late final List<int> decoded;
    try {
      decoded = base64.decode(value);
    } on FormatException {
      throw const BackupFormatException('The backup file is damaged or has an invalid format.');
    }
    if (expectedLength != null && decoded.length != expectedLength) {
      throw const BackupFormatException('The backup file is damaged or has an invalid format.');
    }
    return decoded;
  }

  static void _validatePassword(String password) {
    final length = utf8.encode(password).length;
    if (password.length < 12 || length > _maxPasswordBytes) {
      throw const BackupFormatException('Use a backup password of at least 12 characters (maximum 4096 UTF-8 bytes).');
    }
  }

  static void _validateAccounts(List<TotpAccount> accounts) {
    if (accounts.length > 10000) throw const BackupFormatException('The backup contains too many accounts.');
    final ids = <String>{};
    for (final account in accounts) {
      if (account.id.isEmpty || account.issuer.trim().isEmpty || account.accountName.trim().isEmpty ||
          account.secret.isEmpty || (account.digits != 6 && account.digits != 8) ||
          account.period <= 0 || !ids.add(account.id)) {
        throw const BackupFormatException('The account data is invalid or contains duplicate records.');
      }
      try {
        final code = TotpGenerator.generate(
          secret: account.secret,
          time: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          algorithm: account.algorithm,
          digits: account.digits,
          period: account.period,
        );
        if (code.length != account.digits) throw const FormatException();
      } on Object {
        throw const BackupFormatException('The account data cannot generate a valid verification code.');
      }
    }
  }
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupPasswordException implements Exception {
  const BackupPasswordException();
  @override
  String toString() => 'The password is incorrect, or the backup file is damaged.';
}
