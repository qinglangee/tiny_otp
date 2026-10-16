import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/totp_account.dart';
import '../../data/storage/encrypted_account_repository.dart';
import '../../totp/otpauth_uri_parser.dart';
import '../../totp/totp_generator.dart';
import '../add_account/qr_scanner_page.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, this.repository});

  final AccountRepository? repository;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with WidgetsBindingObserver {
  final List<TotpAccount> _accounts = [];
  late final AccountRepository _repository;
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? EncryptedAccountRepository(keyStore: FlutterDeviceKeyStore());
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTime());
    _loadAccounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshTime();
  }

  void _refreshTime() {
    if (mounted) setState(() => _now = DateTime.now());
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loaded = await _repository.loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });
    } on LocalAccountDataException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = 'The local account store is unavailable. No saved data was changed.';
        _loading = false;
      });
    }
  }

  Future<void> _addAccount() async {
    if (_loading || _loadError != null) return;
    final method = await showModalBottomSheet<_AddMethod>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter details manually'),
              onTap: () => Navigator.pop(context, _AddMethod.manual),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan a setup QR code'),
              subtitle: const Text('Camera access is requested only when scanning starts.'),
              onTap: () => Navigator.pop(context, _AddMethod.scan),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    final account = method == _AddMethod.manual
        ? await showDialog<TotpAccount>(context: context, builder: (_) => const AddAccountDialog())
        : await _scanAndConfirm();
    if (account == null || !mounted) return;
    final duplicate = _accounts.any((existing) =>
        existing.issuer.toLowerCase() == account.issuer.toLowerCase() &&
        existing.accountName.toLowerCase() == account.accountName.toLowerCase());
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This issuer and account name are already in the list.')),
      );
      return;
    }
    final updatedAccounts = [..._accounts, account];
    try {
      await _repository.saveAccounts(updatedAccounts);
      if (mounted) setState(() => _accounts.add(account));
    } on LocalAccountDataException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The account could not be securely saved. No account was added.')),
        );
      }
    }
  }

  Future<TotpAccount?> _scanAndConfirm() async {
    final rawUri = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (rawUri == null || !mounted) return null;
    late final OtpAuthAccountConfig config;
    try {
      config = OtpAuthUriParser.parse(rawUri);
    } on OtpAuthFormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      return null;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm scanned account'),
        content: Text(
          '${config.issuer}\n${config.accountName}\n${config.algorithm.name.toUpperCase()}, ${config.digits} digits, ${config.period} seconds',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (approved != true || !mounted) return null;
    return TotpAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      issuer: config.issuer,
      accountName: config.accountName,
      secret: config.secret,
      algorithm: config.algorithm,
      digits: config.digits,
      period: config.period,
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TinyOTP')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading accounts'))
          : _loadError != null
              ? _StorageErrorState(message: _loadError!, onRetry: _loadAccounts)
              : _accounts.isEmpty
                  ? _EmptyState(onAdd: _addAccount)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final account = _accounts[index];
                try {
                  final code = TotpGenerator.generate(
                    secret: account.secret,
                    time: _now,
                    algorithm: account.algorithm,
                    digits: account.digits,
                    period: account.period,
                  );
                  final remaining = account.period -
                      (_now.toUtc().millisecondsSinceEpoch ~/ 1000) % account.period;
                  return _AccountCard(
                    account: account,
                    code: code,
                    secondsRemaining: remaining,
                    onTap: () => _copyCode(code),
                  );
                } on Object {
                  // One corrupt or unsupported record must not take down the list.
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text(account.issuer),
                      subtitle: const Text('Unable to generate a code for this account.'),
                    ),
                  );
                }
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _loadError != null ? null : _addAccount,
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
    );
  }
}

enum _AddMethod { manual, scan }

class _StorageErrorState extends StatelessWidget {
  const _StorageErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'TinyOTP has not replaced the encrypted data with a new key.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.password_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('No accounts yet', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Add an account to generate verification codes on this device.'),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add account')),
            ],
          ),
        ),
      );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.code,
    required this.secondsRemaining,
    required this.onTap,
  });

  final TotpAccount account;
  final String code;
  final int secondsRemaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = secondsRemaining / account.period;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.issuer, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(account.accountName, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Copy verification code, $code',
                      child: Text(
                        code,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  Text('$secondsRemaining s', semanticsLabel: '$secondsRemaining seconds remaining'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      value: progress,
                      semanticsLabel: '$secondsRemaining seconds remaining',
                      strokeWidth: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _issuer = TextEditingController();
  final _accountName = TextEditingController();
  final _secret = TextEditingController();
  final _period = TextEditingController(text: '30');
  TotpAlgorithm _algorithm = TotpAlgorithm.sha1;
  int _digits = 6;

  @override
  void dispose() {
    _issuer.dispose();
    _accountName.dispose();
    _secret.clear();
    _secret.dispose();
    _period.dispose();
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _reviewAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    final period = int.tryParse(_period.text.trim());
    if (period == null || period < 1 || period > 3600) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Period must be between 1 and 3600 seconds.')),
      );
      return;
    }
    final issuer = _issuer.text.trim();
    final accountName = _accountName.text.trim();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm account'),
        content: Text('$issuer\n$accountName\n${_algorithm.name.toUpperCase()}, $_digits digits, $period seconds'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    try {
      final account = TotpAccount.fromBase32(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        issuer: issuer,
        accountName: accountName,
        secret: _secret.text,
        algorithm: _algorithm,
        digits: _digits,
        period: period,
      );
      Navigator.of(context).pop(account);
    } on FormatException {
      _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add account manually'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _issuer,
                  decoration: const InputDecoration(labelText: 'Issuer / service'),
                  validator: _required,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
                TextFormField(
                  controller: _accountName,
                  decoration: const InputDecoration(labelText: 'Account name'),
                  validator: _required,
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  controller: _secret,
                  decoration: const InputDecoration(labelText: 'Base32 secret'),
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Required';
                    try {
                      TotpAccount.fromBase32(
                        id: 'validation', issuer: 'validation', accountName: 'validation', secret: value,
                      );
                    } on FormatException {
                      return 'Enter a valid Base32 secret.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TotpAlgorithm>(
                  value: _algorithm,
                  decoration: const InputDecoration(labelText: 'Algorithm'),
                  items: TotpAlgorithm.values
                      .map((algorithm) => DropdownMenuItem(
                            value: algorithm,
                            child: Text(algorithm.name.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _algorithm = value ?? TotpAlgorithm.sha1),
                ),
                DropdownButtonFormField<int>(
                  value: _digits,
                  decoration: const InputDecoration(labelText: 'Digits'),
                  items: const [6, 8]
                      .map((digits) => DropdownMenuItem(value: digits, child: Text('$digits digits')))
                      .toList(),
                  onChanged: (value) => setState(() => _digits = value ?? 6),
                ),
                TextFormField(
                  controller: _period,
                  decoration: const InputDecoration(labelText: 'Period (seconds)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed < 1 || parsed > 3600 ? 'Enter 1–3600 seconds.' : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _reviewAndSave, child: const Text('Review')),
        ],
      );
}
