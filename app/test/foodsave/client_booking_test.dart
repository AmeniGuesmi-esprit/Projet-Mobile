import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/core/widgets/money_text.dart';
import 'package:proxilife/features/foodsave/client/booking/booking_format.dart';
import 'package:proxilife/features/foodsave/client/my_reservations_screen.dart';
import 'package:proxilife/features/foodsave/client/reservation_qr_screen.dart';
import 'package:proxilife/features/foodsave/client/reserve_flow.dart';
import 'package:proxilife/features/payment/add_payment_method_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../fakes.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

final DateTime _t0 = DateTime.utc(2026, 10, 13, 17);

Map<String, dynamic> _basketJson({
  int id = 5,
  String titre = 'Panier du soir',
  int quantite = 3,
  int prix = 500,
  int prixInitial = 1500,
}) =>
    {
      'id': id,
      'titre': titre,
      'contenu': 'Pains, viennoiseries',
      'categorie': 'boulangerie',
      'image': null,
      'prix_centimes': prix,
      'prix_initial_centimes': prixInitial,
      'quantite': quantite,
      'quantite_initiale': 10,
      'creneau_retrait_debut': _iso(_t0),
      'creneau_retrait_fin': _iso(_t0.add(const Duration(hours: 2))),
      'date_expiration': _iso(_t0.add(const Duration(hours: 3))),
      'statut': 'disponible',
      'commercant_id': 7,
      'cree_le': _iso(_t0.subtract(const Duration(hours: 1))),
      'commerce': {
        'id': 1,
        'commercant_id': 7,
        'nom': 'Boulangerie du Lac',
        'adresse': '12 rue du Lac Léman, Tunis',
        'latitude': 36.83,
        'longitude': 10.23,
        'categorie': 'boulangerie',
      },
    };

Map<String, dynamic> _reservationJson({
  int id = 9,
  String statut = 'en_attente',
  String paiement = 'paye',
  String? token = 'FS1.9.bm9uY2U.c2ln',
  Duration remaining = const Duration(minutes: 12, seconds: 34),
  String titre = 'Panier du soir',
}) =>
    {
      'id': id,
      'date': _iso(_t0.subtract(const Duration(minutes: 20))),
      'statut': statut,
      'panier_id': 5,
      'client_id': 3,
      'quantite_reservee': 2,
      'montant_centimes': 1000,
      'mode_paiement': 'portefeuille',
      'moyen_paiement_id': 2,
      'statut_paiement': paiement,
      'transaction_id': 44,
      'facture_numero': null,
      'date_creation_qr': _iso(_t0.subtract(const Duration(minutes: 17))),
      'date_expiration_qr': _iso(_t0.add(remaining)),
      'qr_token': token,
      'retire_le': statut == 'retire' ? _iso(_t0) : null,
      'panier': _basketJson(titre: titre),
      'client_nom': null,
    };

const _card = {
  'id': 1,
  'type': 'carte_bancaire',
  'quatre_derniers_chiffres': '4242',
  'nom_titulaire': 'Ameni Guesmi',
  'date_expiration': '12/28',
  'par_defaut': false,
};
const _wallet = {
  'id': 2,
  'type': 'portefeuille',
  'quatre_derniers_chiffres': null,
  'nom_titulaire': null,
  'date_expiration': null,
  'par_defaut': true,
};

/// Fake server: records requests, never touches the network.
class _FakeServer {
  List<Map<String, dynamic>> methods = [_card, _wallet];
  http.Response Function(Map<String, dynamic> body)? onReserve;
  Map<String, dynamic> reservation = _reservationJson();
  List<Map<String, dynamic>> reservations = [];
  final List<http.Request> requests = [];

  static http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  int count(String method, String path) => requests
      .where((r) => r.method == method && r.url.path == path)
      .length;

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final m = request.method;
    if (m == 'GET' && path == '/payment-methods') {
      return json({'items': methods});
    }
    if (m == 'POST' && path == '/foodsave/reservations') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return onReserve?.call(body) ?? json(_reservationJson(), 201);
    }
    if (m == 'GET' && path == '/foodsave/reservations') {
      return json({'items': reservations});
    }
    if (m == 'GET' && path.startsWith('/foodsave/reservations/')) {
      return json(reservation);
    }
    if (m == 'GET' && path.startsWith('/foodsave/baskets/')) {
      return json(_basketJson());
    }
    return json({'error': 'Introuvable'}, 404);
  });
}

SessionController _session(_FakeServer server) {
  final session = makeTestSession(
    api: ApiClient(httpClient: server.client, baseUrl: 'http://fake'),
  );
  session.user = const UserDto(
    id: 3,
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni@example.com',
    telephone: '+21620000000',
    role: UserRole.client,
    statutCompte: AccountStatus.actif,
    soldeCentimes: 2000,
  );
  return session;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

class _FlowHost {
  ReservationDto? result;
  bool closed = false;
}

Future<_FlowHost> _openFlow(WidgetTester tester, _FakeServer server,
    {Map<String, dynamic>? basket}) async {
  _phone(tester);
  final host = _FlowHost();
  final session = _session(server);
  final dto = BasketDto.fromJson(basket ?? _basketJson());
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              host.result = await showReserveFlow(context,
                  session: session, basket: dto);
              host.closed = true;
            },
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
  return host;
}

IconButton _iconButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.text('Continuer'));
  await tester.pumpAndSettle();
}

void main() {
  group('booking format', () {
    test('countdown text and urgency levels', () {
      expect(formatCountdown(const Duration(minutes: 12, seconds: 34)),
          '12:34');
      expect(formatCountdown(const Duration(hours: 1, minutes: 5, seconds: 9)),
          '1:05:09');
      expect(formatCountdown(const Duration(seconds: -3)), '00:00');
      expect(countdownLevel(const Duration(minutes: 11)), CountdownLevel.normal);
      expect(countdownLevel(const Duration(minutes: 9)), CountdownLevel.warning);
      expect(countdownLevel(const Duration(seconds: 90)),
          CountdownLevel.critical);
    });

    test('QR phase follows status, payment and expiry', () {
      final active = ReservationDto.fromJson(_reservationJson());
      expect(qrPhaseOf(active, _t0), QrPhase.active);
      expect(qrPhaseOf(active, _t0.add(const Duration(minutes: 13))),
          QrPhase.expired);
      expect(
          qrPhaseOf(
              ReservationDto.fromJson(
                  _reservationJson(paiement: 'en_attente', token: null)),
              _t0),
          QrPhase.awaitingPayment);
      expect(
          qrPhaseOf(
              ReservationDto.fromJson(
                  _reservationJson(statut: 'retire', token: null)),
              _t0),
          QrPhase.pickedUp);
    });
  });

  group('reserve flow', () {
    testWidgets('quantity is bounded by the stock (1..quantite)',
        (tester) async {
      final server = _FakeServer();
      await _openFlow(tester, server);

      expect(find.text('Étape 1 sur 3'), findsOneWidget);
      expect(_iconButton(tester, 'Diminuer la quantité').onPressed, isNull);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Augmenter la quantité'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(_iconButton(tester, 'Augmenter la quantité').onPressed, isNull);
      expect(_iconButton(tester, 'Diminuer la quantité').onPressed, isNotNull);
      expect(find.text(MoneyText.format(1500)), findsOneWidget); // total
      expect(find.text(MoneyText.format(3000)), findsOneWidget); // savings
    });

    testWidgets('quantity is capped at 20 per reservation', (tester) async {
      final server = _FakeServer();
      await _openFlow(tester, server, basket: _basketJson(quantite: 50));
      for (var i = 0; i < 25; i++) {
        await tester.tap(find.byTooltip('Augmenter la quantité'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget);
      expect(_iconButton(tester, 'Augmenter la quantité').onPressed, isNull);
    });

    testWidgets(
        'default method preselected; confirm reserves with the right params '
        'and pops the reservation', (tester) async {
      final server = _FakeServer();
      Map<String, dynamic>? sent;
      server.onReserve = (body) {
        sent = body;
        return _FakeServer.json(_reservationJson(), 201);
      };
      final host = await _openFlow(tester, server);

      await tester.tap(find.byTooltip('Augmenter la quantité'));
      await tester.pumpAndSettle();
      await _continue(tester);

      expect(find.text('Mode de paiement'), findsOneWidget);
      expect(find.text('Carte •••• 4242'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('payment-method-2')),
              matching: find.byIcon(Icons.radio_button_checked)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('payment-method-1')),
              matching: find.byIcon(Icons.radio_button_unchecked)),
          findsOneWidget);

      await _continue(tester);
      expect(find.text('Récapitulatif'), findsOneWidget);
      expect(find.textContaining('Le QR code expire à la fin du créneau'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reserve-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Réservation confirmée !'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(sent, {'panier_id': 5, 'quantite': 2, 'moyen_paiement_id': 2});
      expect(host.closed, isTrue);
      expect(host.result?.id, 9);
      expect(host.result?.qrToken, isNotNull);
    });

    testWidgets('no payment method shows the add CTA', (tester) async {
      final server = _FakeServer()..methods = [];
      await _openFlow(tester, server);
      await _continue(tester);

      expect(find.text('Aucun moyen de paiement enregistré'), findsOneWidget);
      final cta = find.widgetWithText(OutlinedButton, 'Ajouter un moyen de paiement');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(AddPaymentMethodScreen), findsOneWidget);
    });

    testWidgets('payment refusal (402) is shown inline with a fix',
        (tester) async {
      const message =
          'Paiement refusé : solde insuffisant. Rechargez votre portefeuille ou payez par carte.';
      final server = _FakeServer()
        ..onReserve = (_) => _FakeServer.json({'error': message}, 402);
      final host = await _openFlow(tester, server);
      await _continue(tester);
      await _continue(tester);

      await tester.tap(find.byKey(const ValueKey('reserve-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(host.closed, isFalse);
      await tester.tap(find.text('Changer de moyen de paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Étape 2 sur 3'), findsOneWidget);
    });
  });

  group('QR screen', () {
    testWidgets('shows the QR and countdown, then hides it when expired',
        (tester) async {
      _phone(tester);
      var now = _t0;
      final server = _FakeServer();
      await tester.pumpWidget(MaterialApp(
        home: ReservationQrScreen(
          session: _session(server),
          reservationId: 9,
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Expire dans 12:34'), findsOneWidget);
      expect(find.text('Réf. FS-9'), findsOneWidget);
      expect(find.text('FS1.9.bm9uY2U.c2ln'), findsNothing);
      expect(find.text('Augmentez la luminosité pour faciliter le scan'),
          findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expire dans 12:33'), findsOneWidget);

      // Time runs out: QR hidden, reservation re-fetched.
      server.reservation = _reservationJson(statut: 'expire', token: null);
      now = _t0.add(const Duration(minutes: 13));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('QR code expiré — le panier a été remis en vente'),
          findsOneWidget);
      expect(server.count('GET', '/foodsave/reservations/9'), 2);
      expect(find.text('Annuler la réservation'), findsNothing);
    });

    testWidgets('polling detects the pickup', (tester) async {
      _phone(tester);
      var now = _t0;
      final server = _FakeServer();
      await tester.pumpWidget(MaterialApp(
        home: ReservationQrScreen(
          session: _session(server),
          reservationId: 9,
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);

      server.reservation = _reservationJson(statut: 'retire', token: null);
      now = now.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Retrait validé, bon appétit !'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  group('my reservations', () {
    testWidgets('splits active and history tabs', (tester) async {
      _phone(tester);
      final server = _FakeServer()
        ..reservations = [
          _reservationJson(id: 11, titre: 'Panier du soir'),
          _reservationJson(
              id: 12, statut: 'retire', token: null, titre: 'Panier boulangerie'),
          _reservationJson(
              id: 13,
              statut: 'annule',
              paiement: 'rembourse',
              token: null,
              titre: 'Panier fruits'),
        ];
      await tester.pumpWidget(MaterialApp(
        home: MyReservationsScreen(
          session: _session(server),
          clock: () => _t0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Panier du soir'), findsOneWidget);
      expect(find.text('Expire dans 12:34'), findsOneWidget);
      expect(find.text('Panier boulangerie'), findsNothing);

      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();
      expect(find.text('Panier boulangerie'), findsOneWidget);
      expect(find.text('Panier fruits'), findsOneWidget);
      expect(find.text('Panier du soir'), findsNothing);
      expect(find.text('Remboursé'), findsOneWidget);
    });

    testWidgets('empty state offers a way back to discovery', (tester) async {
      _phone(tester);
      final server = _FakeServer();
      await tester.pumpWidget(MaterialApp(
        home: MyReservationsScreen(session: _session(server), clock: () => _t0),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Aucune réservation en cours'), findsOneWidget);
      expect(find.text('Découvrir les paniers'), findsOneWidget);
    });
  });
}
