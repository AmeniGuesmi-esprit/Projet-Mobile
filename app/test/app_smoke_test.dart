import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/main.dart';

import 'fakes.dart';

void main() {
  testWidgets('Cold start without a stored session shows the login screen',
      (tester) async {
    await tester.pumpWidget(ProxiLifeApp(session: makeTestSession()));
    await tester.pumpAndSettle();

    // Splash disappears, login screen appears.
    expect(find.text('Bienvenue sur ProxiLife'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Se connecter'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
  });

  testWidgets('Login form validates the e-mail before submitting',
      (tester) async {
    await tester.pumpWidget(ProxiLifeApp(session: makeTestSession()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Adresse e-mail'),
        'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Adresse e-mail invalide'), findsOneWidget);
  });
}
