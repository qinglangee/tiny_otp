import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/totp_account.dart';
import '../../data/storage/encrypted_account_repository.dart';
import '../../totp/otpauth_uri_parser.dart';
import '../../totp/totp_generator.dart';
import '../add_account/qr_scanner_page.dart';
import '../backup/backup_page.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, this.repository});

  final AccountRepository? repository;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage>
    with WidgetsBindingObserver {
  final List<TotpAccount> _accounts = [];
  final Map<String, _CachedTotpCode> _codeCache = {};
  late final AccountRepository _repository;
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _loading = true;
  String? _loadError;
  String _searchQuery = '';
  _AccountSortOrder _sortOrder = _AccountSortOrder.issuer;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        EncryptedAccountRepository(keyStore: FlutterDeviceKeyStore());
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

  List<TotpAccount> get _visibleAccounts {
    final query = _searchQuery.trim().toLowerCase();
    final visible = _accounts
        .where(
          (account) =>
              query.isEmpty ||
              account.issuer.toLowerCase().contains(query) ||
              account.accountName.toLowerCase().contains(query),
        )
        .toList();
    visible.sort((left, right) {
      final primary = _sortOrder == _AccountSortOrder.issuer
          ? left.issuer.toLowerCase().compareTo(right.issuer.toLowerCase())
          : left.accountName.toLowerCase().compareTo(
              right.accountName.toLowerCase(),
            );
      return primary != 0
          ? primary
          : left.accountName.toLowerCase().compareTo(
              right.accountName.toLowerCase(),
            );
    });
    return visible;
  }

  Future<void> _editAccount(TotpAccount account) async {
    final edited = await showDialog<TotpAccount>(
      context: context,
      builder: (_) => EditAccountDialog(account: account),
    );
    if (edited == null || !mounted) return;
    final duplicate = _accounts.any(
      (existing) =>
          existing.id != account.id &&
          existing.issuer.toLowerCase() == edited.issuer.toLowerCase() &&
          existing.accountName.toLowerCase() ==
              edited.accountName.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Another account already uses this issuer and name.'),
        ),
      );
      return;
    }
    final updated = _accounts
        .map((item) => item.id == account.id ? edited : item)
        .toList(growable: false);
    await _persistAccountChanges(updated, successMessage: 'Account updated.');
  }

  Future<void> _deleteAccount(TotpAccount account) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'Remove ${account.issuer} (${account.accountName}) from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final updated = _accounts
        .where((item) => item.id != account.id)
        .toList(growable: false);
    await _persistAccountChanges(updated, successMessage: 'Account deleted.');
  }

  Future<void> _persistAccountChanges(
    List<TotpAccount> updated, {
    required String successMessage,
  }) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await _repository.saveAccounts(updated);
      if (!mounted) return;
      setState(() {
        _accounts
          ..clear()
          ..addAll(updated);
        final retainedIds = updated.map((account) => account.id).toSet();
        _codeCache.removeWhere((id, _) => !retainedIds.contains(id));
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } on LocalAccountDataException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage(
        'The account changes could not be securely saved. No changes were applied.',
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showMessage(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  String _codeFor(TotpAccount account, DateTime time) {
    final counter =
        time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ account.period;
    final cached = _codeCache[account.id];
    if (cached != null && cached.counter == counter) return cached.code;
    final code = TotpGenerator.generate(
      secret: account.secret,
      time: time,
      algorithm: account.algorithm,
      digits: account.digits,
      period: account.period,
    );
    _codeCache[account.id] = _CachedTotpCode(counter: counter, code: code);
    return code;
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
        _codeCache.clear();
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
              subtitle: const Text(
                'Camera access is requested only when scanning starts.',
              ),
              onTap: () => Navigator.pop(context, _AddMethod.scan),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    final account = method == _AddMethod.manual
        ? await showDialog<TotpAccount>(
            context: context,
            builder: (_) => const AddAccountDialog(),
          )
        : await _scanAndConfirm();
    if (account == null || !mounted) return;
    final duplicate = _accounts.any(
      (existing) =>
          existing.issuer.toLowerCase() == account.issuer.toLowerCase() &&
          existing.accountName.toLowerCase() ==
              account.accountName.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This issuer and account name are already in the list.',
          ),
        ),
      );
      return;
    }
    final updatedAccounts = [..._accounts, account];
    try {
      await _repository.saveAccounts(updatedAccounts);
      if (mounted) setState(() => _accounts.add(account));
    } on LocalAccountDataException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The account could not be securely saved. No account was added.',
            ),
          ),
        );
      }
    }
  }

  Future<TotpAccount?> _scanAndConfirm() async {
    final rawUri = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrScannerPage()));
    if (rawUri == null || !mounted) return null;
    late final OtpAuthAccountConfig config;
    try {
      config = OtpAuthUriParser.parse(rawUri);
    } on OtpAuthFormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final visibleAccounts = _visibleAccounts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TinyOTP'),
        actions: [
          IconButton(
            tooltip: 'Encrypted backup and restore',
            icon: const Icon(Icons.enhanced_encryption_outlined),
            onPressed: _loading || _loadError != null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BackupPage(repository: _repository),
                      ),
                    );
                    if (mounted) await _loadAccounts();
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading accounts',
              ),
            )
          : _loadError != null
          ? _StorageErrorState(message: _loadError!, onRetry: _loadAccounts)
          : _accounts.isEmpty
          ? _EmptyState(onAdd: _addAccount)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search accounts',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Sort by'),
                      const SizedBox(width: 12),
                      DropdownButton<_AccountSortOrder>(
                        key: const ValueKey('account-sort-order'),
                        value: _sortOrder,
                        onChanged: (value) {
                          if (value != null) setState(() => _sortOrder = value);
                        },
                        items: const [
                          DropdownMenuItem(
                            value: _AccountSortOrder.issuer,
                            child: Text('Issuer'),
                          ),
                          DropdownMenuItem(
                            value: _AccountSortOrder.accountName,
                            child: Text('Account name'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleAccounts.isEmpty
                      ? const Center(child: Text('No matching accounts'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: visibleAccounts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final account = visibleAccounts[index];
                            try {
                              final code = _codeFor(account, _now);
                              final remaining =
                                  account.period -
                                  (_now.toUtc().millisecondsSinceEpoch ~/
                                          1000) %
                                      account.period;
                              return _AccountCard(
                                account: account,
                                code: code,
                                secondsRemaining: remaining,
                                onTap: () => _copyCode(code),
                                onEdit: _mutating
                                    ? null
                                    : () => _editAccount(account),
                                onDelete: _mutating
                                    ? null
                                    : () => _deleteAccount(account),
                              );
                            } on Object {
                              // One corrupt or unsupported record must not take down the list.
                              return Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.warning_amber_rounded,
                                  ),
                                  title: Text(account.issuer),
                                  subtitle: const Text(
                                    'Unable to generate a code for this account.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _loadError != null || _mutating
            ? null
            : _addAccount,
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
    );
  }
}

enum _AddMethod { manual, scan }

enum _AccountSortOrder { issuer, accountName }

class _CachedTotpCode {
  const _CachedTotpCode({required this.counter, required this.code});

  final int counter;
  final String code;
}

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
          Icon(
            Icons.password_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No accounts yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Add an account to generate verification codes on this device.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add account'),
          ),
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
    required this.onEdit,
    required this.onDelete,
  });

  final TotpAccount account;
  final String code;
  final int secondsRemaining;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      account.issuer,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<_AccountAction>(
                    tooltip: 'Account actions',
                    onSelected: (action) => action == _AccountAction.edit
                        ? onEdit?.call()
                        : onDelete?.call(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _AccountAction.edit,
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: _AccountAction.delete,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                account.accountName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Copy verification code, $code',
                      child: Text(
                        code,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  Text(
                    '$secondsRemaining s',
                    semanticsLabel: '$secondsRemaining seconds remaining',
                  ),
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

enum _AccountAction { edit, delete }

class EditAccountDialog extends StatefulWidget {
  const EditAccountDialog({super.key, required this.account});

  final TotpAccount account;

  @override
  State<EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<EditAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _issuer = TextEditingController(
    text: widget.account.issuer,
  );
  late final TextEditingController _accountName = TextEditingController(
    text: widget.account.accountName,
  );

  @override
  void dispose() {
    _issuer.dispose();
    _accountName.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit account details'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _issuer,
            decoration: const InputDecoration(labelText: 'Issuer / service'),
            validator: _required,
          ),
          TextFormField(
            controller: _accountName,
            decoration: const InputDecoration(labelText: 'Account name'),
            validator: _required,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            TotpAccount(
              id: widget.account.id,
              issuer: _issuer.text.trim(),
              accountName: _accountName.text.trim(),
              secret: widget.account.secret,
              algorithm: widget.account.algorithm,
              digits: widget.account.digits,
              period: widget.account.period,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _reviewAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    final period = int.tryParse(_period.text.trim());
    if (period == null || period < 1 || period > 3600) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Period must be between 1 and 3600 seconds.'),
        ),
      );
      return;
    }
    final issuer = _issuer.text.trim();
    final accountName = _accountName.text.trim();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm account'),
        content: Text(
          '$issuer\n$accountName\n${_algorithm.name.toUpperCase()}, $_digits digits, $period seconds',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
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
                    id: 'validation',
                    issuer: 'validation',
                    accountName: 'validation',
                    secret: value,
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
                  .map(
                    (algorithm) => DropdownMenuItem(
                      value: algorithm,
                      child: Text(algorithm.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _algorithm = value ?? TotpAlgorithm.sha1),
            ),
            DropdownButtonFormField<int>(
              value: _digits,
              decoration: const InputDecoration(labelText: 'Digits'),
              items: const [6, 8]
                  .map(
                    (digits) => DropdownMenuItem(
                      value: digits,
                      child: Text('$digits digits'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _digits = value ?? 6),
            ),
            TextFormField(
              controller: _period,
              decoration: const InputDecoration(labelText: 'Period (seconds)'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                return parsed == null || parsed < 1 || parsed > 3600
                    ? 'Enter 1–3600 seconds.'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _reviewAndSave, child: const Text('Review')),
    ],
  );
}
