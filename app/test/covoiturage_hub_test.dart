import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/trips/covoiturage_hub_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'fakes.dart';

SessionController _session(UserRole role) {
  final session = makeTestSession(
    api: ApiClient(
      baseUrl: 'http://fake',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({'items': <Object>[]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    ),
  );
  session.user = UserDto(
    id: 1,
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni@example.com',
    telephone: '+21620000000',
    role: role,
    statutCompte: AccountStatus.actif,
    soldeCentimes: 0,
  );
  return session;
}

Future<void> _pump(WidgetTester tester, UserRole role) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(home: CovoiturageHubScreen(session: _session(role))));
  await tester.pump();
}

void main() {
  test('every role has the Covoiturage tab', () {
    for (final role in UserRole.values) {
      expect(CovoiturageHubScreen.availableFor(role), isTrue, reason: '$role');
    }
    expect(CovoiturageHubScreen.availableFor(null), isFalse);
  });

  for (final role in [
    UserRole.commercant,
    UserRole.medecin,
    UserRole.coach,
    UserRole.admin,
  ]) {
    testWidgets('${role.apiValue}: same passenger tabs as a client',
        (tester) async {
      await _pump(tester, role);
      expect(find.widgetWithText(Tab, 'Rechercher'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Réservations'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Mes trajets'), findsNothing);
    });
  }

  testWidgets('passenger: Rechercher + Réservations, a single app bar',
      (tester) async {
    await _pump(tester, UserRole.client);
    expect(find.text('EcoRoute'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Rechercher'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Réservations'), findsOneWidget);
    // The embedded screens no longer show their own title bar.
    expect(find.text('Rechercher un trajet'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('driver: Mes trajets + Demandes', (tester) async {
    await _pump(tester, UserRole.conducteur);
    expect(find.widgetWithText(Tab, 'Mes trajets'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Demandes'), findsOneWidget);
    expect(find.text('Demandes reçues'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Demandes'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
