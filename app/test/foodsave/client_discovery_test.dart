import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/foodsave/client/basket_detail_screen.dart';
import 'package:proxilife/features/foodsave/client/basket_map_view.dart';
import 'package:proxilife/features/foodsave/client/client_discovery_screen.dart';
import 'package:proxilife/features/foodsave/platform/location_service.dart';

import '../fakes.dart';

/// GPS fake: no platform channel is ever touched.
class FakeGeo extends GeoBackend {
  FakeGeo({this.permission = GeoPermission.granted, this.position});

  GeoPermission permission;
  ({double latitude, double longitude})? position;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<GeoPermission> checkPermission() async => permission;
  @override
  Future<GeoPermission> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<({double latitude, double longitude})?> currentPosition() async =>
      position;
  @override
  Future<({double latitude, double longitude})?> lastKnownPosition() async =>
      position;
  @override
  Future<void> openAppSettings() async => settingsOpened++;
  @override
  Future<void> openLocationSettings() async => settingsOpened++;
}

String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, dynamic> basketJson({
  required int id,
  required String titre,
  String statut = 'disponible',
  int quantite = 3,
  int prix = 500,
  int prixInitial = 1500,
  double? distance = 1.2,
  int storeId = 7,
  String storeName = 'Boulangerie du Lac',
}) {
  final now = DateTime.now().toUtc();
  return {
    'id': id,
    'titre': titre,
    'contenu': 'Pains, viennoiseries et douceurs du jour',
    'categorie': 'boulangerie',
    'image': null,
    'prix_centimes': prix,
    'prix_initial_centimes': prixInitial,
    'quantite': quantite,
    'quantite_initiale': 5,
    'creneau_retrait_debut': _iso(now.add(const Duration(hours: 1))),
    'creneau_retrait_fin': _iso(now.add(const Duration(hours: 2))),
    'date_expiration': _iso(now.add(const Duration(hours: 5))),
    'statut': statut,
    'commercant_id': 99,
    'cree_le': _iso(now.subtract(const Duration(hours: 1))),
    'commerce': {
      'id': storeId,
      'commercant_id': 99,
      'nom': storeName,
      'adresse': '12 rue du Lac, Tunis',
      'latitude': 36.81,
      'longitude': 10.19,
      'categorie': 'boulangerie',
    },
    'distance_km': distance,
  };
}

class Harness {
  Harness({List<Map<String, dynamic>>? items, this.detail})
      : items = items ?? [];

  List<Map<String, dynamic>> items;
  Map<String, dynamic>? detail;
  final List<http.Request> requests = [];

  List<Uri> get basketListCalls => requests
      .where((r) => r.method == 'GET' && r.url.path == '/foodsave/baskets')
      .map((r) => r.url)
      .toList();

  SessionController session() {
    final client = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path == '/foodsave/baskets') {
        return _json({'items': items});
      }
      if (path.startsWith('/foodsave/baskets/')) {
        return _json(detail!);
      }
      if (path == '/foodsave/location') {
        return _json({'message': 'Position enregistrée'});
      }
      return _json({'error': 'Introuvable'}, 404);
    });
    final api = ApiClient(httpClient: client, baseUrl: 'http://test')
      ..token = 'tok';
    return makeTestSession(api: api);
  }

  static http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json'});
}

late FakeGeo geo;

Future<void> _pumpDiscovery(WidgetTester tester, Harness h) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
      MaterialApp(home: ClientDiscoveryScreen(session: h.session())));
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(WidgetTester tester, Harness h) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: BasketDetailScreen(session: h.session(), basketId: 1)));
  await tester.pumpAndSettle();
}

ButtonStyleButton _buttonWithText(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));

void main() {
  setUp(() {
    geo = FakeGeo(position: (latitude: 36.8065, longitude: 10.1815));
    FoodSaveLocationService.instance
      ..backend = geo
      ..reset();
    FoodSaveMapTiles.debugTileLayer = () => const SizedBox.shrink();
  });

  tearDown(() => FoodSaveMapTiles.debugTileLayer = null);

  group('ClientDiscoveryScreen', () {
    testWidgets('renders cards in server order with discount and GPS position',
        (tester) async {
      final h = Harness(items: [
        basketJson(id: 2, titre: 'Panier du soir', quantite: 2),
        basketJson(id: 1, titre: 'Viennoiseries', storeId: 8),
      ]);
      await _pumpDiscovery(tester, h);

      expect(find.text('Paniers anti-gaspi'), findsOneWidget);
      expect(find.text('2 paniers près de chez vous'), findsOneWidget);
      final first = tester.getTopLeft(find.text('Panier du soir')).dy;
      final second = tester.getTopLeft(find.text('Viennoiseries')).dy;
      expect(first, lessThan(second));
      expect(find.text('-67 %'), findsNWidgets(2));
      expect(find.text('Plus que 2'), findsOneWidget);
      expect(find.textContaining("Retrait aujourd'hui").evaluate().isNotEmpty ||
              find.textContaining('Retrait demain').evaluate().isNotEmpty,
          isTrue);

      // The GPS fix was pushed to the server and used for the listing.
      expect(
          h.requests.any(
              (r) => r.method == 'PUT' && r.url.path == '/foodsave/location'),
          isTrue);
      final last = h.basketListCalls.last;
      expect(last.queryParameters['lat'], '36.8065');
      expect(last.queryParameters['lng'], '10.1815');
      expect(last.queryParameters['tri'], 'distance');
    });

    testWidgets('shows the empty state', (tester) async {
      await _pumpDiscovery(tester, Harness());
      expect(find.text('Aucun panier près de chez vous pour le moment'),
          findsOneWidget);
    });

    testWidgets('category chip reloads with the categorie parameter',
        (tester) async {
      final h = Harness(items: [basketJson(id: 1, titre: 'Viennoiseries')]);
      await _pumpDiscovery(tester, h);
      final before = h.basketListCalls.length;

      await tester.tap(find.text('Boulangerie'));
      await tester.pumpAndSettle();

      expect(h.basketListCalls.length, before + 1);
      expect(h.basketListCalls.last.queryParameters['categorie'],
          'boulangerie');

      await tester.tap(find.text('Toutes'));
      await tester.pumpAndSettle();
      expect(h.basketListCalls.last.queryParameters.containsKey('categorie'),
          isFalse);
    });

    testWidgets('filters: Tout (default), -50 % et +', (tester) async {
      final h = Harness(items: [basketJson(id: 1, titre: 'Viennoiseries')]);
      await _pumpDiscovery(tester, h);
      expect(find.text('Tout'), findsOneWidget);
      expect(find.text('Prix'), findsNothing);
      final first = h.basketListCalls.last.queryParameters;
      expect(first['tri'], 'distance');
      expect(first.containsKey('rayon_km'), isFalse);
      expect(first.containsKey('reduction_min'), isFalse);

      await tester.tap(find.text('-50 % et +'));
      await tester.pumpAndSettle();
      final q = h.basketListCalls.last.queryParameters;
      expect(q['reduction_min'], '50');
      expect(q['tri'], 'reduction');

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      expect(h.basketListCalls.last.queryParameters.containsKey('reduction_min'),
          isFalse);
    });

    testWidgets('search is debounced (350 ms)', (tester) async {
      final h = Harness(items: [basketJson(id: 1, titre: 'Viennoiseries')]);
      await _pumpDiscovery(tester, h);
      final before = h.basketListCalls.length;

      await tester.enterText(find.byType(TextField), 'pa');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'pain');
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.basketListCalls.length, before,
          reason: 'no request while the user is typing');

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(h.basketListCalls.length, before + 1);
      expect(h.basketListCalls.last.queryParameters['q'], 'pain');
    });

    testWidgets('≤ 3 km sends the radius; without position: no request',
        (tester) async {
      final h = Harness(items: [basketJson(id: 1, titre: 'Viennoiseries')]);
      await _pumpDiscovery(tester, h);
      await tester.tap(find.text('≤ 3 km'));
      await tester.pumpAndSettle();
      final q = h.basketListCalls.last.queryParameters;
      expect(q['rayon_km'], '3.0');
      expect(q['tri'], 'distance');
      expect(q['lat'], isNotNull);

      geo
        ..permission = GeoPermission.denied
        ..position = null;
      FoodSaveLocationService.instance.reset();
      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      final before = h.basketListCalls.length;
      await tester.tap(find.text('≤ 3 km'));
      await tester.pumpAndSettle();
      expect(h.basketListCalls.length, before);
      expect(find.text('Aucun panier à 3 km ou moins'), findsOneWidget);
      expect(
          find.text(
              'Activez la localisation pour voir les paniers proches de vous.'),
          findsOneWidget);
    });

    testWidgets('location denied shows the banner and can retry',
        (tester) async {
      geo
        ..permission = GeoPermission.denied
        ..position = null;
      final h = Harness(items: [basketJson(id: 1, titre: 'Viennoiseries', distance: null)]);
      await _pumpDiscovery(tester, h);

      expect(
          find.text(
              'Activez la localisation pour voir la distance et recevoir les paniers à moins de 5 km'),
          findsOneWidget);
      expect(find.text('1 panier disponible'), findsOneWidget);
      expect(h.basketListCalls.last.queryParameters.containsKey('lat'),
          isFalse);

      final asked = geo.requests;
      geo
        ..permission = GeoPermission.granted
        ..position = (latitude: 36.8, longitude: 10.2);
      await tester.tap(find.text('Activer la localisation'));
      await tester.pumpAndSettle();

      expect(geo.requests, asked); // already granted: no new prompt needed
      expect(find.text('Activer la localisation'), findsNothing);
      expect(h.basketListCalls.last.queryParameters['lat'], '36.8');
    });

    testWidgets('list ⇄ map toggle shows price markers and a preview',
        (tester) async {
      final h = Harness(items: [
        basketJson(id: 2, titre: 'Panier du soir'),
        basketJson(id: 1, titre: 'Viennoiseries', prix: 300),
      ]);
      await _pumpDiscovery(tester, h);

      await tester.tap(find.byTooltip('Afficher la carte'));
      await tester.pumpAndSettle();
      expect(find.byType(BasketMapView), findsOneWidget);
      expect(find.byTooltip('Afficher la liste'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('store-marker-7')));
      await tester.pumpAndSettle();
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
      expect(find.byTooltip('Fermer l\'aperçu'), findsOneWidget);
    });
  });

  group('BasketDetailScreen', () {
    testWidgets('disponible: enabled Réserver, discount and stock',
        (tester) async {
      final h = Harness(detail: basketJson(id: 1, titre: 'Panier du soir'));
      await _pumpDetail(tester, h);

      expect(find.text('Panier du soir'), findsOneWidget);
      expect(find.text('-67 %'), findsOneWidget);
      expect(find.text('Il reste 3 paniers'), findsOneWidget);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
      expect(_buttonWithText(tester, 'Réserver').onPressed, isNotNull);
    });

    for (final c in [
      (statut: 'epuise', quantite: 0, chip: 'Épuisé'),
      (statut: 'annule', quantite: 2, chip: 'Annulé'),
    ]) {
      testWidgets('${c.statut}: disabled CTA with the reason', (tester) async {
        final h = Harness(
            detail: basketJson(
                id: 1,
                titre: 'Panier du soir',
                statut: c.statut,
                quantite: c.quantite));
        await _pumpDetail(tester, h);

        expect(find.text('Réserver'), findsNothing);
        expect(_buttonWithText(tester, 'Réservation indisponible').onPressed,
            isNull);
        expect(find.text(c.chip), findsWidgets);
      });
    }

    testWidgets('pickup window closed: disabled CTA', (tester) async {
      final json = basketJson(id: 1, titre: 'Panier du soir');
      final now = DateTime.now().toUtc();
      json['creneau_retrait_debut'] =
          _iso(now.subtract(const Duration(hours: 2)));
      json['creneau_retrait_fin'] =
          _iso(now.add(const Duration(minutes: 2)));
      await _pumpDetail(tester, Harness(detail: json));

      expect(find.textContaining('Réservations closes depuis'),
          findsOneWidget);
      expect(_buttonWithText(tester, 'Réservation indisponible').onPressed,
          isNull);
    });

    Map<String, dynamic> closingBasket(Duration left) {
      final now = DateTime.now().toUtc();
      final json = basketJson(id: 1, titre: 'Panier du soir');
      json['creneau_retrait_debut'] =
          _iso(now.subtract(const Duration(hours: 1)));
      json['creneau_retrait_fin'] = _iso(now.add(left));
      json['date_expiration'] = _iso(now.add(left));
      json['duree_reservation_minutes'] = 15;
      return json;
    }

    testWidgets('15-min reservations, expires in 20 min: still reservable',
        (tester) async {
      await _pumpDetail(tester,
          Harness(detail: closingBasket(const Duration(minutes: 20))));
      expect(_buttonWithText(tester, 'Réserver').onPressed, isNotNull);
      expect(find.textContaining('Réservable jusqu\'à'), findsOneWidget);
      expect(find.textContaining('retrait sous 15 min'), findsOneWidget);
    });

    testWidgets('15-min reservations, expires in 10 min: button disabled',
        (tester) async {
      await _pumpDetail(tester,
          Harness(detail: closingBasket(const Duration(minutes: 10))));
      expect(find.textContaining('durée de réservation est de 15 min'),
          findsOneWidget);
      expect(_buttonWithText(tester, 'Réservation indisponible').onPressed,
          isNull);
    });
  });
}
