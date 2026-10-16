import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/data/models/totp_account.dart';
import 'package:tinyotp/data/storage/encrypted_account_repository.dart';
import 'package:tinyotp/features/accounts/accounts_page.dart';

void main() {
  testWidgets('manually adds an account after review and displays its code', (tester) async {
    final repository = _MemoryAccountRepository();
    await tester.pumpWidget(MaterialApp(home: AccountsPage(repository: repository)));
    await tester.pump();

    expect(find.text('No accounts yet'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Example Service');
    await tester.enterText(find.byType(TextFormField).at(1), 'sample@example.test');
    await tester.enterText(find.byType(TextFormField).at(2), 'JBSWY3DPEHPK3PXP');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm account'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 500));

    final accountCard = find.byType(Card);
    expect(find.descendant(of: accountCard, matching: find.text('Example Service')), findsOneWidget);
    expect(find.descendant(of: accountCard, matching: find.text('sample@example.test')), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text && RegExp(r'^\d{6}$').hasMatch(widget.data ?? '')),
      findsOneWidget,
    );
    expect(find.text('No accounts yet'), findsNothing);
    expect(repository.accounts, hasLength(1));
  });
}

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
