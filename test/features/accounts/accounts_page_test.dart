import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/features/accounts/accounts_page.dart';

void main() {
  testWidgets('manually adds an account after review and displays its code', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AccountsPage()));

    expect(find.text('No accounts yet'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Example Service');
    await tester.enterText(find.byType(TextFormField).at(1), 'sample@example.test');
    await tester.enterText(find.byType(TextFormField).at(2), 'JBSWY3DPEHPK3PXP');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm account'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Example Service'), findsOneWidget);
    expect(find.text('sample@example.test'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text && RegExp(r'^\d{6}$').hasMatch(widget.data ?? '')),
      findsOneWidget,
    );
    expect(find.text('No accounts yet'), findsNothing);
  });
}
