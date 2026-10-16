import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/data/models/totp_account.dart';
import 'package:tinyotp/data/storage/encrypted_account_repository.dart';
import 'package:tinyotp/features/accounts/accounts_page.dart';

void main() {
  testWidgets('manually adds an account after review and displays its code', (
    tester,
  ) async {
    final repository = _MemoryAccountRepository();
    await tester.pumpWidget(
      MaterialApp(home: AccountsPage(repository: repository)),
    );
    await tester.pump();

    expect(find.text('No accounts yet'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Example Service');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'sample@example.test',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'JBSWY3DPEHPK3PXP',
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm account'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 500));

    final accountCard = find.byType(Card);
    expect(
      find.descendant(of: accountCard, matching: find.text('Example Service')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: accountCard,
        matching: find.text('sample@example.test'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && RegExp(r'^\d{6}$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(find.text('No accounts yet'), findsNothing);
    expect(repository.accounts, hasLength(1));
  });

  testWidgets('searches accounts by issuer and account name', (tester) async {
    final repository = _MemoryAccountRepository()
      ..accounts = [
        _sampleAccount('Alpha', 'alice@test'),
        _sampleAccount('Beta', 'bob@test'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: AccountsPage(repository: repository)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'bob@test');
    await tester.pump();

    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('sorts accounts by the selected field', (tester) async {
    final repository = _MemoryAccountRepository()
      ..accounts = [
        _sampleAccount('Zulu', 'alpha@test'),
        _sampleAccount('Alpha', 'zulu@test'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: AccountsPage(repository: repository)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('account-sort-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account name').last);
    await tester.pump();

    final first = tester.getTopLeft(find.text('Zulu').first).dy;
    final second = tester.getTopLeft(find.text('Alpha').first).dy;
    expect(first, lessThan(second));
  });

  testWidgets('edits an account label without changing its secret', (
    tester,
  ) async {
    final original = _sampleAccount('Example', 'user@test');
    final repository = _MemoryAccountRepository()..accounts = [original];
    await tester.pumpWidget(
      MaterialApp(home: AccountsPage(repository: repository)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Account actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed'), findsOneWidget);
    expect(repository.accounts.single.secret, original.secret);
  });

  testWidgets('requires confirmation before deleting an account', (
    tester,
  ) async {
    final repository = _MemoryAccountRepository()
      ..accounts = [_sampleAccount('Example', 'user@test')];
    await tester.pumpWidget(
      MaterialApp(home: AccountsPage(repository: repository)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Account actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsOneWidget);
    expect(repository.accounts, hasLength(1));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.accounts, isEmpty);
  });
}

TotpAccount _sampleAccount(String issuer, String name) => TotpAccount(
  id: '$issuer-$name',
  issuer: issuer,
  accountName: name,
  secret: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
);

class _MemoryAccountRepository implements AccountRepository {
  List<TotpAccount> accounts = [];

  @override
  Future<List<TotpAccount>> loadAccounts() async => List.unmodifiable(accounts);

  @override
  Future<void> saveAccounts(List<TotpAccount> accounts) async {
    this.accounts = List.unmodifiable(accounts);
  }

  @override
  Future<void> rotateEncryptionKey() async {}
}
