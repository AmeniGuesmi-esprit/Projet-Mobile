import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/core/widgets/money_text.dart';
import 'package:proxilife/features/foodsave/merchant/basket_form_screen.dart';
import 'package:proxilife/features/foodsave/merchant/merchant_baskets_screen.dart';
import 'package:proxilife/features/foodsave/merchant/scan_result_view.dart';
import 'package:proxilife/features/foodsave/merchant/scan_screen.dart';
import 'package:proxilife/features/foodsave/merchant/widgets/basket_form_validators.dart';
import 'package:proxilife/features/foodsave/merchant/widgets/basket_photo_field.dart';
import 'package:proxilife/features/foodsave/merchant/widgets/merchant_format.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../fakes.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, dynamic> basketJson({
  required int id,
  required String titre,
  String statut = 'disponible',
  int quantite = 3,
  int quantiteInitiale = 5,
  int reservationsActives = 1,
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'titre': titre,
    'contenu': 'Viennoiseries et pain du jour',
    'categorie': 'boulangerie',
    'image': null,
    'prix_centimes': 500,
    'prix_initial_centimes': 1500,
    'quantite': quantite,
    'quantite_initiale': quantiteInitiale,
    'creneau_retrait_debut': _iso(now.add(const Duration(hours: 1))),
    'creneau_retrait_fin': _iso(now.add(const Duration(hours: 3))),
    'date_expiration': _iso(now.add(const Duration(hours: 4))),
    'statut': statut,
    'commercant_id': 7,
    'cree_le': _iso(now.subtract(const Duration(hours: 1))),
    'reservations_actives': reservationsActives,
  };
}

Map<String, dynamic> reservationJson({String statut = 'retire'}) => {
      'id': 42,
      'date': _iso(DateTime.now()),
      'statut': statut,
      'panier_id': 1,
      'client_id': 9,
      'quantite_reservee': 2,
      'montant_centimes': 1000,
      'statut_paiement': 'paye',
      'client_nom': 'Ameni G.',
      'panier': basketJson(id: 1, titre: 'Panier du soir'),
    };

/// Records requests and answers from [handler].
class _Server {
  _Server(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  ApiClient get api => ApiClient(
        baseUrl: 'http://fake',
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      )..token = 'test-token';
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light(), home: home);

void main() {
  group('parseDinarsToCents', () {
    test('parses comma and dot decimals without doubles', () {
      expect(parseDinarsToCents('12,5'), 1250);
      expect(parseDinarsToCents('0,99'), 99);
      expect(parseDinarsToCents('12'), 1200);
      expect(parseDinarsToCents('12.50'), 1250);
      expect(parseDinarsToCents(' 7,05 '), 705);
      expect(parseDinarsToCents('0'), 0);
    });

    test('rejects invalid amounts', () {
      expect(parseDinarsToCents('1,234'), isNull);
      expect(parseDinarsToCents(''), isNull);
      expect(parseDinarsToCents('abc'), isNull);
      expect(parseDinarsToCents('-5'), isNull);
      expect(parseDinarsToCents('1.2.3'), isNull);
    });

    test('centsToInput round-trips', () {
      expect(centsToInput(1250), '12,50');
      expect(centsToInput(99), '0,99');
      expect(parseDinarsToCents(centsToInput(123456)), 123456);
    });
  });

  group('basket form validators', () {
    test('initial price must be greater than the reduced price', () {
      expect(validateInitialPrice('10', '10'),
          'Le prix initial doit être supérieur au prix réduit');
      expect(validateInitialPrice('5,00', '10'),
          'Le prix initial doit être supérieur au prix réduit');
      expect(validateInitialPrice('30', '10'), isNull);
    });

    test('quantity rules', () {
      expect(validateBasketQuantity('0', creating: true),
          'La quantité doit être d\'au moins 1');
      expect(validateBasketQuantity('-1', creating: false),
          'La quantité ne peut pas être négative');
      expect(validateBasketQuantity('0', creating: false), isNull);
      expect(validateBasketQuantity('1000', creating: true),
          'Quantité trop élevée (999 maximum)');
    });

    test('image type is detected from magic bytes', () {
      expect(detectImageContentType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(
          detectImageContentType([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          'image/png');
      expect(detectImageContentType([0x47, 0x49, 0x46]), isNull);
    });
  });

  testWidgets('baskets list renders from JSON and filters by status',
      (tester) async {
    final server = _Server((request) async {
      expect(request.url.path, '/foodsave/merchant/baskets');
      return _json({
        'items': [
          basketJson(id: 1, titre: 'Panier du soir'),
          basketJson(
              id: 2,
              titre: 'Pains de la veille',
              statut: 'epuise',
              quantite: 0,
              reservationsActives: 2),
        ],
      });
    });
    final session = makeTestSession(api: server.api);

    await tester.pumpWidget(_app(MerchantBasketsScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Panier du soir'), findsOneWidget);
    expect(find.text('Pains de la veille'), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
    expect(find.text('Nouveau panier'), findsOneWidget);
    expect(find.text('Tous · 2'), findsOneWidget);

    await tester.tap(find.text('Épuisés · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Panier du soir'), findsNothing);
    expect(find.text('Pains de la veille'), findsOneWidget);

    await tester.ensureVisible(find.text('Annulés · 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulés · 0'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun panier avec ce statut'), findsOneWidget);
  });

  testWidgets('baskets list shows the empty state', (tester) async {
    final server = _Server((_) async => _json({'items': <Object>[]}));
    await tester.pumpWidget(_app(
        MerchantBasketsScreen(session: makeTestSession(api: server.api))));
    await tester.pumpAndSettle();
    expect(find.text('Aucun panier publié'), findsOneWidget);
  });

  group('basket form', () {
    void tallView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 4800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    Future<void> fill(
      WidgetTester tester, {
      required String price,
      required String initial,
      String quantity = '3',
    }) async {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Titre'), 'Panier du soir');
      await tester.enterText(find.widgetWithText(TextFormField, 'Contenu'),
          'Trois viennoiseries et une baguette');
      await tester.enterText(find.byKey(const ValueKey('field-price')), price);
      await tester.enterText(
          find.byKey(const ValueKey('field-initial-price')), initial);
      await tester.enterText(
          find.byKey(const ValueKey('field-quantity')), quantity);
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.text('Publier le panier');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('initial price lower or equal to reduced price is refused',
        (tester) async {
      tallView(tester);
      final server = _Server((_) async => _json({}, 500));
      await tester.pumpWidget(
          _app(BasketFormScreen(session: makeTestSession(api: server.api))));
      await fill(tester, price: '10', initial: '10');
      await submit(tester);

      expect(find.text('Le prix initial doit être supérieur au prix réduit'),
          findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('zero quantity is refused at creation', (tester) async {
      tallView(tester);
      final server = _Server((_) async => _json({}, 500));
      await tester.pumpWidget(
          _app(BasketFormScreen(session: makeTestSession(api: server.api))));
      await fill(tester, price: '5', initial: '15', quantity: '0');
      await submit(tester);

      expect(find.text('La quantité doit être d\'au moins 1'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('only durations that fit between start and expiry',
        (tester) async {
      tallView(tester);
      // 22:00 → 23:00 style: a one-hour sale.
      final json = basketJson(id: 3, titre: 'Panier du soir');
      final start = DateTime.parse(json['creneau_retrait_debut'] as String);
      json['creneau_retrait_fin'] =
          _iso(start.add(const Duration(hours: 1)));
      json['date_expiration'] = _iso(start.add(const Duration(hours: 1)));
      final server = _Server((_) async => _json({}, 500));
      await tester.pumpWidget(_app(BasketFormScreen(
          session: makeTestSession(api: server.api),
          basket: BasketDto.fromJson(json))));
      await tester.pumpAndSettle();

      for (final m in [15, 30, 45, 60]) {
        expect(find.byKey(ValueKey('duration-$m')), findsOneWidget,
            reason: '$m min');
      }
      expect(find.byKey(const ValueKey('duration-90')), findsNothing);
      expect(find.byKey(const ValueKey('duration-120')), findsNothing);
    });

    testWidgets('start date + expiry + reservation duration, no "Fin"',
        (tester) async {
      tallView(tester);
      final server = _Server((request) async => _json({
            'panier': basketJson(id: 6, titre: 'Panier du soir'),
            'clients_notifies': 0,
          }, 201));
      await tester.pumpWidget(
          _app(BasketFormScreen(session: makeTestSession(api: server.api))));

      expect(find.text('Date de début'), findsOneWidget);
      expect(find.text('Créneau de retrait'), findsNothing);
      expect(find.text('Fin'), findsNothing);
      expect(find.text('Durée de réservation'), findsOneWidget);

      await fill(tester, price: '5', initial: '15');
      final chip = find.byKey(const ValueKey('duration-45'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await submit(tester);

      final body =
          jsonDecode(server.requests.single.body) as Map<String, dynamic>;
      expect(body['duree_reservation_minutes'], 45);
    });

    testWidgets('live discount preview and successful publication',
        (tester) async {
      tallView(tester);
      final server = _Server((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/foodsave/merchant/baskets');
        return _json({
          'panier': basketJson(id: 5, titre: 'Panier du soir'),
          'clients_notifies': 3,
        }, 201);
      });
      BasketDto? popped;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<BasketDto>(
                    MaterialPageRoute(
                        builder: (_) => BasketFormScreen(
                            session: makeTestSession(api: server.api))));
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await fill(tester, price: '12,5', initial: '30');
      expect(find.text('-58 %'), findsOneWidget);
      expect(find.text('Le client économise ${MoneyText.format(1750)}'),
          findsOneWidget);

      await submit(tester);

      expect(server.requests, hasLength(1));
      final body =
          jsonDecode(server.requests.single.body) as Map<String, dynamic>;
      expect(body['prix_centimes'], 1250);
      expect(body['prix_initial_centimes'], 3000);
      expect(body['quantite'], 3);
      expect((body['creneau_retrait_fin'] as String).endsWith('Z'), isTrue);
      // New form: start = now, pickup until the expiry (2 h later by
      // default), default reservation duration.
      final start = DateTime.parse(body['creneau_retrait_debut'] as String);
      expect(DateTime.now().difference(start).inMinutes.abs(), lessThan(2));
      expect(body['creneau_retrait_fin'], body['date_expiration']);
      expect(
          DateTime.parse(body['date_expiration'] as String).difference(start),
          const Duration(hours: 2));
      expect(body['duree_reservation_minutes'], 30);
      expect(popped?.id, 5);
      expect(find.text('Panier publié · 3 clients à proximité notifiés'),
          findsOneWidget);
    });
  });

  group('scan', () {
    testWidgets('accepted result shows the pickup details', (tester) async {
      final result = ScanResultDto.fromJson({
        'resultat': 'accepte',
        'message': 'Retrait validé : remettez 2 × Panier du soir à Ameni G.',
        'reservation': reservationJson(),
      });
      var again = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: ScanResultView(
            result: result, onScanAgain: () => again++, onDone: () {}),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Retrait validé'), findsOneWidget);
      expect(find.text('Ameni G.'), findsOneWidget);
      expect(find.text('Panier du soir'), findsOneWidget);
      expect(find.text('× 2'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.text('Scanner un autre code'));
      expect(again, 1);
    });

    testWidgets('expired result explains what to do', (tester) async {
      final result = ScanResultDto.fromJson({
        'resultat': 'expire',
        'message': 'Ce QR code a expiré.',
        'reservation': null,
      });
      await tester.pumpWidget(_app(Scaffold(
        body: ScanResultView(
            result: result, onScanAgain: () {}, onDone: () {}),
      )));
      await tester.pumpAndSettle();

      expect(find.text('QR code expiré'), findsOneWidget);
      expect(find.text('Ce QR code a expiré.'), findsOneWidget);
      expect(find.textContaining('Ne remettez pas le panier'), findsOneWidget);
      expect(find.text('Terminer'), findsOneWidget);
    });

    testWidgets('manual code entry submits the token to the server',
        (tester) async {
      final server = _Server((request) async {
        expect(request.url.path, '/foodsave/merchant/scan');
        return _json({
          'resultat': 'accepte',
          'message': 'Retrait validé : remettez 2 × Panier du soir à Ameni G.',
          'reservation': reservationJson(),
        });
      });
      await tester.pumpWidget(_app(ScanScreen(
        session: makeTestSession(api: server.api),
        scannerBuilder: (context, onCode) =>
            const ColoredBox(color: Colors.black),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Saisir le code'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('manual-code-field')), '  FS1.42.abc.def ');
      await tester.tap(find.text('Valider le retrait'));
      await tester.pumpAndSettle();

      expect(server.requests, hasLength(1));
      final body =
          jsonDecode(server.requests.single.body) as Map<String, dynamic>;
      expect(body['token'], 'FS1.42.abc.def');
      expect(find.text('Retrait validé'), findsOneWidget);
      expect(find.text('Ameni G.'), findsOneWidget);
    });

    testWidgets('same scanned code is ignored within 3 seconds',
        (tester) async {
      final server = _Server((_) async => _json({
            'resultat': 'invalide',
            'message': 'QR code non reconnu.',
            'reservation': null,
          }));
      late ValueChanged<String> emit;
      await tester.pumpWidget(_app(ScanScreen(
        session: makeTestSession(api: server.api),
        scannerBuilder: (context, onCode) {
          emit = onCode;
          return const ColoredBox(color: Colors.black);
        },
      )));
      emit('FS1.1.a.b');
      await tester.pumpAndSettle();
      expect(find.text('QR code invalide'), findsOneWidget);

      await tester.tap(find.text('Scanner un autre code'));
      await tester.pumpAndSettle();
      emit('FS1.1.a.b'); // still in front of the camera
      await tester.pumpAndSettle();
      expect(server.requests, hasLength(1));
      expect(find.text('QR code invalide'), findsNothing);
    });
  });
}
