import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/data/backup/encrypted_backup_service.dart';
import 'package:tinyotp/data/models/totp_account.dart';

void main() {
  const password = 'backup-passphrase-test-only';
  final account = TotpAccount(
    id: 'test-account-1',
    issuer: 'Example Service',
    accountName: 'user@example.test',
    secret: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  );

  group('EncryptedBackupService', () {
    test('encrypts account data and restores it with the independent password', () async {
      final service = EncryptedBackupService();
      final bytes = await service.createBackup(accounts: [account], password: password);
      expect(utf8.decode(bytes), isNot(contains(base64Url.encode(account.secret))));
      expect(utf8.decode(bytes), isNot(contains('user@example.test')));

      final restored = await service.restoreBackup(bytes: bytes, password: password);
      expect(restored, hasLength(1));
      expect(restored.single.issuer, account.issuer);
      expect(restored.single.accountName, account.accountName);
      expect(restored.single.secret, account.secret);
    });

    test('rejects an incorrect backup password', () async {
      final service = EncryptedBackupService();
      final bytes = await service.createBackup(accounts: [account], password: password);
      await expectLater(
        service.restoreBackup(bytes: bytes, password: 'another-test-password'),
        throwsA(isA<BackupPasswordException>()),
      );
    });

    test('rejects corrupt input without throwing an unhandled parser error', () async {
      await expectLater(
        EncryptedBackupService().restoreBackup(bytes: utf8.encode('{invalid'), password: password),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('requires a long password and limits oversized files', () async {
      final service = EncryptedBackupService();
      await expectLater(
        service.createBackup(accounts: [account], password: 'short'),
        throwsA(isA<BackupFormatException>()),
      );
      await expectLater(
        service.restoreBackup(
          bytes: List<int>.filled(EncryptedBackupService.maxBackupBytes + 1, 0),
          password: password,
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
}
