import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/foodsave/client/basket_detail_screen.dart';
import 'package:proxilife/features/foodsave/client/client_discovery_screen.dart';
import 'package:proxilife/features/foodsave/client/reservation_qr_screen.dart';
import 'package:proxilife/features/foodsave/data/foodsave_api.dart';
import 'package:proxilife/features/foodsave/merchant/merchant_basket_detail_screen.dart';
import 'package:proxilife/features/foodsave/merchant/merchant_dashboard_screen.dart';
import 'package:proxilife/features/foodsave/merchant/merchant_reservations_screen.dart';
import 'package:proxilife/features/foodsave/platform/foodsave_hub_screen.dart';
import 'package:proxilife/features/foodsave/platform/foodsave_navigation.dart';
import 'package:proxilife/features/foodsave/platform/foodsave_notification_poller.dart';
import 'package:proxilife/features/foodsave/platform/foodsave_notifications_screen.dart';
import 'package:proxilife/features/foodsave/platform/foodsave_platform_hooks.dart';
import 'package:proxilife/features/foodsave/platform/location_service.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../fakes.dart';

// ------------------------------------------------------------------ fakes

class FakeGeo extends GeoBackend {
  bool serviceEnabled = true;
  GeoPermission permission = GeoPermission.granted;
  GeoPermission afterRequest = GeoPermission.granted;
  ({double latitude, double longitude})? fix = (latitude: 36.8, longitude: 10.18);
  ({double latitude, double longitude})? lastKnown;
  bool throwOnCurrent = false;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;
  @override
  Future<GeoPermission> checkPermission() async => permission;
  @override
  Future<GeoPermission> requestPermission() async {
    requests++;
    permission = afterRequest;
    return permission;
  }

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    if (throwOnCurrent) throw Exception('timeout');
    return fix;
  }

  @override
  Future<({double latitude, double longitude})?> lastKnownPosition() async =>
      lastKnown;
  @override
  Future<void> openAppSettings() async => settingsOpened++;
  @override
  Future<void> openLocationSettings() async => settingsOpened++;
}

/// Records every request; answers from [handler].
class FakeServer {
  FakeServer(this.handler);

  http.Response Function(http.Request request) handler;
  final List<String> calls = [];

  late final MockClient client = MockClient((request) async {
    calls.add('${request.method} ${request.url.path}'
        '${request.url.hasQuery ? '?${request.url.query}' : ''}');
    return handler(request);
  });

  int count(String call) => calls.where((c) => c == call).length;
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

SessionController authedSession(FakeServer server,
    {UserRole role = UserRole.client}) {
  final session = makeTestSession(
      api: ApiClient(httpClient: server.client, baseUrl: 'http://test'));
  session.api.token = 'token';
  session.user = UserDto(
    id: 7,
    nom: 'G.',
    prenom: 'Ameni',
    email: 'ameni@example.com',
    telephone: '+21620000000',
    role: role,
    statutCompte: AccountStatus.actif,
    soldeCentimes: 0,
  );
  session.status = SessionStatus.authenticated;
  return session;
}

Map<String, dynamic> notif(
  int id, {
  FoodSaveNotificationType type = FoodSaveNotificationType.nouveauPanier,
  bool lu = false,
  int? panierId,
  int? reservationId,
  DateTime? at,
}) =>
    FoodSaveNotificationDto(
      id: id,
      type: type,
      titre: 'Titre $id',
      message: 'Message $id',
      lu: lu,
      creeLe: (at ?? DateTime.now()).toUtc(),
      panierId: panierId,
      reservationId: reservationId,
    ).toJson();

void main() {
  final shown = <({String title, String body, String? payload})>[];
  var permissionRequests = 0;
  final flags = <String, bool>{};

  setUp(() {
    shown.clear();
    permissionRequests = 0;
    flags.clear();
    FoodSavePlatformHooks.showNotification =
        ({required String title, required String body, String? payload}) async =>
            shown.add((title: title, body: body, payload: payload));
    FoodSavePlatformHooks.requestNotificationPermission = () async {
      permissionRequests++;
      return true;
    };
    FoodSavePlatformHooks.readFlag = (key) async => flags[key] ?? false;
    FoodSavePlatformHooks.writeFlag = (key, value) async => flags[key] = value;
    FoodSaveNotificationPoller.instance.stop();
    FoodSaveLocationService.instance
      ..backend = (FakeGeo()..serviceEnabled = false)
      ..reset();
    FoodSaveHubScreen.resetSessionState();
  });

  // ------------------------------------------------------------- location

  group('FoodSaveLocationService', () {
    late FakeGeo geo;
    late FakeServer server;
    late FoodSaveApi api;
    late DateTime now;
    final service = FoodSaveLocationService.instance;

    setUp(() {
      geo = FakeGeo();
      server = FakeServer((_) => jsonResponse({'message': 'ok'}));
      api = FoodSaveApi(
          ApiClient(httpClient: server.client, baseUrl: 'http://test'));
      now = DateTime.utc(2026, 10, 13, 12);
      service
        ..backend = geo
        ..clock = (() => now)
        ..reset();
    });

    test('pushes the position, then re-syncs only after 5 min', () async {
      final r = await service.refresh(api);
      expect(r.hasPosition, isTrue);
      expect(service.last?.latitude, 36.8);
      expect(server.count('PUT /foodsave/location'), 1);

      now = now.add(const Duration(minutes: 2));
      await service.refresh(api);
      expect(server.count('PUT /foodsave/location'), 1);

      now = now.add(const Duration(minutes: 4));
      await service.refresh(api);
      expect(server.count('PUT /foodsave/location'), 2);
    });

    test('a significant move re-syncs immediately', () async {
      await service.refresh(api);
      geo.fix = (latitude: 36.85, longitude: 10.18); // ~5.5 km north
      await service.refresh(api);
      expect(server.count('PUT /foodsave/location'), 2);
    });

    test('asks permission only when allowed to', () async {
      geo
        ..permission = GeoPermission.denied
        ..afterRequest = GeoPermission.denied;
      final silent = await service.refresh(api, askPermission: false);
      expect(silent.issue, LocationIssue.permissionDenied);
      expect(geo.requests, 0);

      geo.afterRequest = GeoPermission.granted;
      final asked = await service.refresh(api);
      expect(asked.hasPosition, isTrue);
      expect(geo.requests, 1);
    });

    test('denied forever clears the server copy once', () async {
      geo.permission = GeoPermission.deniedForever;
      final r = await service.refresh(api);
      expect(r.issue, LocationIssue.permissionDeniedForever);
      await service.refresh(api);
      expect(server.count('DELETE /foodsave/location'), 1);
      expect(server.count('PUT /foodsave/location'), 0);
    });

    test('service disabled: no request, settings opener targets location',
        () async {
      geo.serviceEnabled = false;
      final r = await service.refresh(api);
      expect(r.issue, LocationIssue.serviceDisabled);
      expect(server.calls, isEmpty);
      await service.openSettings(LocationIssue.serviceDisabled);
      expect(geo.settingsOpened, 1);
    });

    test('falls back to the last known position, then unavailable', () async {
      geo
        ..throwOnCurrent = true
        ..lastKnown = (latitude: 36.7, longitude: 10.1);
      final r = await service.currentPosition();
      expect(r.latitude, 36.7);
      expect(server.calls, isEmpty, reason: 'currentPosition never syncs');

      geo.lastKnown = null;
      final none = await service.currentPosition();
      expect(none.issue, LocationIssue.unavailable);
    });

    test('network errors are swallowed and retried next time', () async {
      server.handler = (_) => throw http.ClientException('offline');
      final r = await service.refresh(api);
      expect(r.hasPosition, isTrue);
      server.handler = (_) => jsonResponse({'message': 'ok'});
      await service.refresh(api);
      expect(server.count('PUT /foodsave/location'), 2);
    });
  });

  // ------------------------------------------------------- formatting/nav

  test('formatRelativeFr', () {
    final now = DateTime(2026, 10, 13, 18, 0);
    expect(formatRelativeFr(now.subtract(const Duration(seconds: 20)), now),
        'À l\'instant');
    expect(formatRelativeFr(now.subtract(const Duration(minutes: 5)), now),
        'Il y a 5 min');
    expect(formatRelativeFr(now.subtract(const Duration(hours: 3)), now),
        'Il y a 3 h');
    expect(formatRelativeFr(DateTime(2026, 10, 12, 9, 5), now),
        'Hier à 09:05');
    expect(formatRelativeFr(DateTime(2026, 10, 10, 9), now), 'Il y a 3 j');
    expect(formatRelativeFr(DateTime(2026, 9, 1, 9), now), '01/09/2026');
  });

  test('payloads map to the right screen per role', () {
    final server = FakeServer((_) => jsonResponse({}));
    final client = authedSession(server);
    final merchant = authedSession(server, role: UserRole.commercant);

    expect(
        foodSavePayloadFor(FoodSaveNotificationDto.fromJson(
            notif(1, panierId: 4))),
        'basket:4');
    expect(
        foodSavePayloadFor(FoodSaveNotificationDto.fromJson(
            notif(2, panierId: 4, reservationId: 9))),
        'reservation:9');
    expect(foodSavePayloadFor(FoodSaveNotificationDto.fromJson(notif(3))),
        'foodsave');

    final basket = foodSaveScreenForPayload('basket:4', client);
    expect(basket, isA<BasketDetailScreen>());
    expect((basket! as BasketDetailScreen).basketId, 4);
    final qr = foodSaveScreenForPayload('reservation:9', client);
    expect((qr! as ReservationQrScreen).reservationId, 9);
    expect(foodSaveScreenForPayload('basket:4', merchant),
        isA<MerchantBasketDetailScreen>());
    expect(foodSaveScreenForPayload('reservation:9', merchant),
        isA<MerchantReservationsScreen>());
    expect(foodSaveScreenForPayload('foodsave', client),
        isA<FoodSaveNotificationsScreen>());
    expect(foodSaveScreenForPayload('payment:3', client), isNull);
    expect(foodSaveScreenForPayload('basket:x', client), isNull);
  });

  // --------------------------------------------------------------- poller

  testWidgets('poller shows each new unread notification once',
      (tester) async {
    final now = DateTime.now();
    var items = [
      notif(1, panierId: 10, at: now.subtract(const Duration(hours: 2))),
      notif(2, panierId: 11, at: now.subtract(const Duration(minutes: 1))),
    ];
    final server = FakeServer((r) => r.url.path == '/foodsave/notifications'
        ? jsonResponse({'items': items})
        : jsonResponse({}, 404));
    final session = authedSession(server);
    final poller = FoodSaveNotificationPoller.instance;

    poller.start(session);
    await tester.pump();
    await poller.poll();

    expect(server.calls.first, 'GET /foodsave/notifications?non_lues=1');
    expect(poller.unreadCount, 2);
    // Old unread ones (before start) only feed the badge.
    expect(shown.map((s) => s.payload), ['basket:11']);

    await poller.poll();
    expect(shown, hasLength(1), reason: 'never shown twice');

    items = [
      notif(3,
          type: FoodSaveNotificationType.reservationConfirmee,
          reservationId: 5,
          at: now.subtract(const Duration(hours: 1))),
      ...items,
    ];
    await poller.poll();
    expect(poller.unreadCount, 3);
    expect(shown.map((s) => s.payload), ['basket:11', 'reservation:5']);
    expect(shown.last.title, 'Titre 3');

    // Periodic tick.
    final before = server.calls.length;
    await tester.pump(FoodSaveNotificationPoller.interval);
    await tester.pump();
    expect(server.calls.length, greaterThan(before));

    // Signed out: stops and resets.
    poller.stop();
    expect(poller.isRunning, isFalse);
    expect(poller.unreadCount, 0);
    final afterStop = server.calls.length;
    await tester.pump(FoodSaveNotificationPoller.interval * 2);
    expect(server.calls.length, afterStop);
  });

  testWidgets('poller survives server errors', (tester) async {
    final server = FakeServer((_) => jsonResponse({'error': 'Oups'}, 500));
    final poller = FoodSaveNotificationPoller.instance
      ..start(authedSession(server));
    await tester.pump();
    await poller.poll();
    expect(poller.unreadCount, 0);
    expect(shown, isEmpty);
    poller.stop();
  });

  // --------------------------------------------------- notifications screen

  Future<void> pumpScreen(WidgetTester tester, SessionController session) async {
    await tester.pumpWidget(MaterialApp(
      home: FoodSaveNotificationsScreen(session: session),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('notifications screen: list, mark read, open target',
      (tester) async {
    final server = FakeServer((r) => switch (r.url.path) {
          '/foodsave/notifications' => jsonResponse({
              'items': [
                notif(1, panierId: 42),
                notif(2,
                    type: FoodSaveNotificationType.retraitEffectue,
                    reservationId: 8,
                    lu: true,
                    at: DateTime.now().subtract(const Duration(hours: 3))),
              ]
            }),
          _ => jsonResponse({'message': 'ok'}),
        });
    final session = authedSession(server);
    await pumpScreen(tester, session);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.text('Titre 2'), findsOneWidget);
    expect(find.text('Il y a 3 h'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Non lue\. Titre 1')),
        findsOneWidget);
    expect(FoodSaveNotificationPoller.instance.unreadCount, 1);

    await tester.tap(find.text('Titre 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(server.count('POST /foodsave/notifications/1/read'), 1);
    expect(FoodSaveNotificationPoller.instance.unreadCount, 0);
    expect(find.byType(BasketDetailScreen), findsOneWidget);
    expect(
        tester.widget<BasketDetailScreen>(find.byType(BasketDetailScreen))
            .basketId,
        42);

    // Replace the tree so the pushed screen is disposed cleanly.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('notifications screen: mark all as read', (tester) async {
    final server = FakeServer((r) => r.url.path == '/foodsave/notifications'
        ? jsonResponse({
            'items': [notif(1, panierId: 1), notif(2, panierId: 2)]
          })
        : jsonResponse({'message': 'ok'}));
    await pumpScreen(tester, authedSession(server));

    await tester.tap(find.byTooltip('Tout marquer comme lu'));
    await tester.pumpAndSettle();

    expect(server.count('POST /foodsave/notifications/read-all'), 1);
    expect(find.text('Toutes les notifications sont marquées comme lues'),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Non lue')), findsNothing);
    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.done_all_rounded),
        matching: find.byType(IconButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('notifications screen: empty and error states', (tester) async {
    final server =
        FakeServer((_) => jsonResponse({'items': <Object>[]}));
    await pumpScreen(tester, authedSession(server));
    expect(find.text('Aucune notification'), findsOneWidget);

    final failing =
        FakeServer((_) => jsonResponse({'error': 'Service indisponible'}, 503));
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, authedSession(failing));
    expect(find.text('Service indisponible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  // ------------------------------------------------------------------ hub

  Future<void> pumpHub(WidgetTester tester, SessionController session) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FoodSaveHubScreen(session: session)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('hub: client sees discovery + one-time permission card',
      (tester) async {
    final server = FakeServer((_) => jsonResponse({}, 404));
    final geo = FakeGeo()..serviceEnabled = false;
    FoodSaveLocationService.instance.backend = geo;
    await pumpHub(tester, authedSession(server));

    expect(find.byType(ClientDiscoveryScreen), findsOneWidget);
    expect(find.byType(MerchantDashboardScreen), findsNothing);
    expect(find.text('Paniers anti-gaspillage près de chez vous'),
        findsOneWidget);
    // Location read once for this app session, without a permission prompt.
    expect(FoodSaveLocationService.instance.last?.issue,
        LocationIssue.serviceDisabled);
    expect(geo.requests, 0);

    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paniers anti-gaspillage près de chez vous'),
        findsNothing);
    expect(flags[FoodSaveHubScreen.permissionPromptFlag], isTrue);
    expect(permissionRequests, 0);
    await disposeTree(tester);

    // Next visit: no card any more.
    await pumpHub(tester, authedSession(server));
    expect(find.text('Activer'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('hub: merchant sees dashboard; Activer asks notifications',
      (tester) async {
    final server = FakeServer((_) => jsonResponse({}, 404));
    await pumpHub(tester, authedSession(server, role: UserRole.commercant));

    expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    expect(find.byType(ClientDiscoveryScreen), findsNothing);
    expect(find.text('Ne manquez aucune réservation'), findsOneWidget);
    expect(FoodSaveLocationService.instance.last, isNull,
        reason: 'merchants are not geolocated by the hub');

    await tester.tap(find.text('Activer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(permissionRequests, 1);
    expect(flags[FoodSaveHubScreen.permissionPromptFlag], isTrue);
    expect(
        find.text(
            'Notifications activées : vous serez averti des réservations.'),
        findsOneWidget);
    await disposeTree(tester);
  });
}
