import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/widgets/money_text.dart';
import 'package:proxilife/core/widgets/status_chip.dart';
import 'package:proxilife/features/payment/payment_api.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

void main() {
  group('parseAmountToCents', () {
    test('parses French and dot decimals', () {
      expect(parseAmountToCents('12'), 1200);
      expect(parseAmountToCents('12,50'), 1250);
      expect(parseAmountToCents('12.5'), 1250);
      expect(parseAmountToCents('0,09'), 9);
    });

    test('rejects invalid or zero amounts', () {
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('0'), isNull);
      expect(parseAmountToCents('-5'), isNull);
      expect(parseAmountToCents('1,234'), isNull);
    });
  });

  testWidgets('StatusChip shows French labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusChip(TransactionStatus.paye),
        ),
      ),
    );
    expect(find.text('Payé'), findsOneWidget);
  });

  testWidgets('MoneyText formats euros with the French currency pattern',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MoneyText(2599))),
    );
    expect(find.textContaining('25'), findsWidgets);
    expect(find.textContaining('€'), findsWidgets);
  });
}
