import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/features/home/home_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

void main() {
  Future<List<String>> pumpHome(WidgetTester tester, UserRole role) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            session: teledocSession(role),
            onOpenTab: opened.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  Future<void> disposeHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('Paiements, FoodSave, EcoRoute, then TeleDoc cards', (
    tester,
  ) async {
    await pumpHome(tester, UserRole.client);

    final pay = tester.getTopLeft(find.text('Vos paiements'));
    final food = tester.getTopLeft(
      find.text('Paniers anti-gaspi près de vous'),
    );
    final eco = tester.getTopLeft(find.text('Trouver un covoiturage'));
    final tele = tester.getTopLeft(
      find.text('Consulter un médecin à distance'),
    );
    expect(pay.dy, lessThan(food.dy));
    expect(food.dy, lessThan(eco.dy));
    expect(eco.dy, lessThan(tele.dy));
    await disposeHome(tester);
  });

  testWidgets('Cards open the Paiements, FoodSave and EcoRoute tabs', (
    tester,
  ) async {
    final opened = await pumpHome(tester, UserRole.client);

    await tester.tap(find.text('Vos paiements'));
    await tester.tap(find.text('Paniers anti-gaspi près de vous'));
    await tester.tap(find.text('Trouver un covoiturage'));
    expect(opened, ['payments', 'foodsave', 'covoiturage']);
    await disposeHome(tester);
  });

  testWidgets('Merchant and driver get their own wording', (tester) async {
    await pumpHome(tester, UserRole.commercant);
    expect(find.text('Revenus versés sur votre RIB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Gérer vos paniers anti-gaspi'), findsOneWidget);
    await disposeHome(tester);

    await pumpHome(tester, UserRole.conducteur);
    expect(find.text('Vos trajets en covoiturage'), findsOneWidget);
    await disposeHome(tester);
  });
}
