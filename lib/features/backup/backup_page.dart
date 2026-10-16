import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/backup/encrypted_backup_service.dart';
import '../../data/storage/encrypted_account_repository.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.repository, this.backupService});

  final AccountRepository repository;
  final EncryptedBackupService? backupService;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final EncryptedBackupService _backupService = widget.backupService ?? EncryptedBackupService();
  bool _busy = false;

  Future<void> _export() async {
    final password = await _requestPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final accounts = await widget.repository.loadAccounts();
      final bytes = await _backupService.createBackup(accounts: accounts, password: password);
      final result = await FilePicker.saveFile(
        dialogTitle: 'Save encrypted TinyOTP backup',
        fileName: 'tinyotp-backup.tinyotp',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/octet-stream',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result == null ? 'Backup export cancelled.' : 'Encrypted backup saved. Keep its password safe.')),
      );
    } on BackupFormatException catch (error) {
      _showMessage(error.message);
    } on LocalAccountDataException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('The encrypted backup could not be created or saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['tinyotp'],
      );
      if (file == null || !mounted) return;
      final length = file.lengthSync() ?? await file.length();
      if (length == null || length <= 0 || length > EncryptedBackupService.maxBackupBytes) {
        _showMessage('The selected backup file is empty or too large.');
        return;
      }
      final bytes = await file.readAsBytes();
      final password = await _requestPassword(confirm: false);
      if (password == null || !mounted) return;
      final accounts = await _backupService.restoreBackup(bytes: bytes, password: password);
      if (!mounted) return;
      final current = await widget.repository.loadAccounts();
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review backup restore'),
          content: Text(current.isEmpty
              ? 'This backup contains ${accounts.length} accounts. Restore them to this device?'
              : 'This backup contains ${accounts.length} accounts. Restoring will replace all ${current.length} existing accounts. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await widget.repository.saveAccounts(accounts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored ${accounts.length} accounts and protected them with this device’s local key.')),
      );
    } on BackupPasswordException {
      _showMessage('The password is incorrect, or the backup file is damaged.');
    } on BackupFormatException catch (error) {
      _showMessage(error.message);
    } on LocalAccountDataException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('The backup could not be restored. Existing accounts were not intentionally replaced.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _requestPassword({required bool confirm}) async {
    final password = TextEditingController();
    final repeated = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirm ? 'Set backup password' : 'Enter backup password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Backup password'),
                validator: (value) => (value?.length ?? 0) < 12 ? 'Use at least 12 characters.' : null,
              ),
              if (confirm)
                TextFormField(
                  controller: repeated,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (value) => value != password.text ? 'Passwords do not match.' : null,
                ),
              const SizedBox(height: 12),
              const Text('This password is independent of your device key. TinyOTP cannot recover a forgotten backup password.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, password.text);
            },
            child: Text(confirm ? 'Create backup' : 'Unlock backup'),
          ),
        ],
      ),
    );
    password.clear();
    repeated.clear();
    password.dispose();
    repeated.dispose();
    return result;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Encrypted backup')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.enhanced_encryption_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Backups are encrypted with a separate password before they are saved. Choose a password you can keep safe; it cannot be reset.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Create encrypted backup'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Restore from backup'),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator(semanticsLabel: 'Processing encrypted backup')),
            ],
          ],
        ),
      );
}
