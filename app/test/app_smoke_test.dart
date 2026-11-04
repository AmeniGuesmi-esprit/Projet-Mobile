import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/main.dart';

import 'fakes.dart';

void main() {
  testWidgets('Cold start without a stored session shows the landing page',
      (tester) async {
    // Phone-sized view, wide enough for the test font.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    _disableAnimations(tester);
    await tester.pumpWidget(ProxiLifeApp(session: makeTestSession()));
    await tester.pumpAndSettle();

    // Splash disappears, landing page with the services and two buttons.
    expect(find.text('Nos services'), findsOneWidget);
    for (final name in ['EcoRoute', 'FoodSave', 'TeleDoc Express']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    expect(find.byKey(const ValueKey('landing-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('landing-register')), findsOneWidget);

    // « Se connecter » → login screen; back arrow → landing page again.
    await tester.tap(find.byKey(const ValueKey('landing-login')));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue sur ProxiLife'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Nos services'), findsOneWidget);

    // « Créer un compte » → registration form.
    await tester.tap(find.byKey(const ValueKey('landing-register')));
    await tester.pumpAndSettle();
    expect(find.text('Nos services'), findsNothing);
  });

  testWidgets('Login form validates the e-mail before submitting',
      (tester) async {
    _disableAnimations(tester);
    await tester.pumpWidget(ProxiLifeApp(session: makeTestSession()));
    await tester.pumpAndSettle();
    // The buttons sit below the illustration: scroll on small screens.
    await tester.ensureVisible(find.byKey(const ValueKey('landing-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('landing-login')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Adresse e-mail'),
        'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Adresse e-mail invalide'), findsOneWidget);
  });
}

/// The landing illustration floats forever; like the phone's "reduce
/// motion" setting, this stops it so pumpAndSettle can settle.
void _disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}
