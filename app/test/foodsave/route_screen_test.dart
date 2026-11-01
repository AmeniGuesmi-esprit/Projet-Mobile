import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/features/foodsave/client/route_screen.dart';
import 'package:proxilife/features/foodsave/data/foodsave_api.dart';
import 'package:proxilife/features/foodsave/platform/location_service.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

const _store = StoreDto(
  id: 1,
  commercantId: 7,
  nom: 'Boulangerie Ameni',
  adresse: 'Cite Des Martyrs, Tunis',
  latitude: 36.7751,
  longitude: 10.1718,
  categorie: FoodCategory.boulangerie,
);

void main() {
  group('formatting', () {
    test('duration and distance in French', () {
      expect(routeDurationFr(20), '1 min');
      expect(routeDurationFr(397), '7 min');
      expect(routeDurationFr(3714), '1 h 02');
      expect(routeDistanceFr(847), '850 m');
      expect(routeDistanceFr(5295), '5,3 km');
      expect(routeDistanceFr(24400), '24 km');
    });

    test('Google Maps directions link', () {
      final uri = googleMapsDirectionsUri(_store, TravelMode.pied);
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['destination'], '36.7751,10.1718');
      expect(uri.queryParameters['travelmode'], 'walking');
      expect(
          googleMapsDirectionsUri(_store, TravelMode.voiture)
              .queryParameters['travelmode'],
          'driving');
    });
  });

  late List<http.Request> requests;
  late List<Uri> launched;

  FoodSaveApi api() => FoodSaveApi(ApiClient(
        baseUrl: 'http://fake',
        httpClient: MockClient((request) async {
          requests.add(request);
          final walking = request.url.queryParameters['mode'] == 'pied';
          return http.Response(
            jsonEncode(RouteDto(
              mode: walking ? TravelMode.pied : TravelMode.voiture,
              distanceMetres: walking ? 4644 : 5295,
              dureeSecondes: walking ? 3714 : 397,
              points: const [(36.8064, 10.1814), (36.7751, 10.1718)],
            ).toJson()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ));

  Future<void> pump(WidgetTester tester,
      {double? lat, double? lng, LocationResult? fix}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: RouteScreen(
        api: api(),
        store: _store,
        fromLatitude: lat,
        fromLongitude: lng,
        locate: () async =>
            fix ?? const LocationResult(issue: LocationIssue.unavailable),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
        clock: () => DateTime(2026, 10, 27, 21, 40),
        tileLayer: const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    requests = [];
    launched = [];
  });

  testWidgets('car route by default, then on foot', (tester) async {
    await pump(tester, lat: 36.8064, lng: 10.1814);

    expect(find.text('Itinéraire'), findsOneWidget);
    expect(find.text('7 min'), findsOneWidget);
    expect(find.text('· 5,3 km'), findsOneWidget);
    expect(find.text('En voiture · arrivée vers 21:47'), findsOneWidget);
    final first = requests.single.url;
    expect(first.path, '/foodsave/geo/route');
    expect(first.queryParameters['mode'], 'voiture');
    expect(first.queryParameters['to_lat'], '36.7751');

    await tester.tap(find.text('À pied'));
    await tester.pumpAndSettle();
    expect(find.text('1 h 02'), findsOneWidget);
    expect(find.text('· 4,6 km'), findsOneWidget);
    expect(requests.last.url.queryParameters['mode'], 'pied');

    // Back to the car: cached, no new request.
    await tester.tap(find.text('Voiture'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));

    await tester.tap(find.text('Démarrer dans Google Maps'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['travelmode'], 'driving');
  });

  testWidgets('uses the GPS when no start is given', (tester) async {
    await pump(tester,
        fix: const LocationResult(latitude: 36.81, longitude: 10.18));
    expect(requests.single.url.queryParameters['from_lat'], '36.81');
    expect(find.text('7 min'), findsOneWidget);
  });

  testWidgets('no position: French explanation, Google Maps still works',
      (tester) async {
    await pump(tester,
        fix: const LocationResult(issue: LocationIssue.permissionDenied));
    expect(requests, isEmpty);
    expect(
        find.text(FoodSaveLocationService.messageFor(
            LocationIssue.permissionDenied)),
        findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Démarrer dans Google Maps'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['destination'], '36.7751,10.1718');
  });
}
