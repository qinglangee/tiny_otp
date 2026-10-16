import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/data/models/totp_account.dart';
import 'package:tinyotp/data/storage/encrypted_account_repository.dart';
import 'package:tinyotp/totp/totp_generator.dart';

void main() {
  late Directory supportDirectory;
  late _MemoryKeyStore keyStore;
  late EncryptedAccountRepository repository;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('tinyotp-encrypted-store-');
    keyStore = _MemoryKeyStore();
    repository = EncryptedAccountRepository(
      keyStore: keyStore,
      supportDirectoryProvider: () async => supportDirectory,
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) await supportDirectory.delete(recursive: true);
  });

  test('persists authenticated ciphertext and reloads account data', () async {
    final account = _sampleAccount();
    await repository.saveAccounts([account]);

    final storeFile = File(
      '${supportDirectory.path}${Platform.pathSeparator}tinyotp${Platform.pathSeparator}accounts.v1.enc.json',
    );
    final diskContents = await storeFile.readAsString();
    expect(diskContents, isNot(contains('12345678901234567890')));
    expect(diskContents, isNot(contains('JBSWY3DPEHPK3PXP')));

    final loaded = await repository.loadAccounts();
    expect(loaded, hasLength(1));
    expect(loaded.single.issuer, account.issuer);
    expect(loaded.single.accountName, account.accountName);
    expect(loaded.single.secret, account.secret);
    expect(loaded.single.algorithm, TotpAlgorithm.sha512);
  });

  test('refuses to recreate a missing key or overwrite the encrypted file', () async {
    await repository.saveAccounts([_sampleAccount()]);
    final storeFile = File(
      '${supportDirectory.path}${Platform.pathSeparator}tinyotp${Platform.pathSeparator}accounts.v1.enc.json',
    );
    final before = await storeFile.readAsString();
    keyStore.values.clear();

    await expectLater(repository.loadAccounts(), throwsA(isA<LocalEncryptionKeyUnavailableException>()));
    await expectLater(repository.saveAccounts(const []), throwsA(isA<LocalEncryptionKeyUnavailableException>()));
    expect(await storeFile.readAsString(), before);
  });

  test('rejects an invalid authentication tag and preserves the source file', () async {
    await repository.saveAccounts([_sampleAccount()]);
    final storeFile = File(
      '${supportDirectory.path}${Platform.pathSeparator}tinyotp${Platform.pathSeparator}accounts.v1.enc.json',
    );
    final envelope = jsonDecode(await storeFile.readAsString()) as Map<String, dynamic>;
    envelope['mac'] = base64Url.encode(List<int>.filled(16, 0));
    await storeFile.writeAsString(jsonEncode(envelope), flush: true);
    final corrupted = await storeFile.readAsString();

    await expectLater(repository.loadAccounts(), throwsA(isA<LocalAccountDataException>()));
    expect(await storeFile.readAsString(), corrupted);
    await expectLater(repository.saveAccounts(const []), throwsA(isA<LocalAccountDataException>()));
  });

  test('rotates the data key and retains readable accounts', () async {
    await repository.saveAccounts([_sampleAccount()]);
    expect(keyStore.values, hasLength(1));

    await repository.rotateEncryptionKey();

    expect(keyStore.values, hasLength(1));
    expect((await repository.loadAccounts()).single.accountName, 'sample@example.test');
  });

  test('uses a fresh nonce for each encryption under a key', () async {
    await repository.saveAccounts([_sampleAccount()]);
    final storeFile = File(
      '${supportDirectory.path}${Platform.pathSeparator}tinyotp${Platform.pathSeparator}accounts.v1.enc.json',
    );
    final first = jsonDecode(await storeFile.readAsString()) as Map<String, dynamic>;
    await repository.saveAccounts([_sampleAccount()]);
    final second = jsonDecode(await storeFile.readAsString()) as Map<String, dynamic>;

    expect(second['nonce'], isNot(first['nonce']));
  });
}

TotpAccount _sampleAccount() => TotpAccount.fromBase32(
      id: 'sample-account-1',
      issuer: 'Example Service',
      accountName: 'sample@example.test',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha512,
      digits: 8,
      period: 45,
    );

class _MemoryKeyStore implements DeviceKeyStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
