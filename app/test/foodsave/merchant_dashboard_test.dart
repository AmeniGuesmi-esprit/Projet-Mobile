import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/foodsave/merchant/charts/chart_format.dart';
import 'package:proxilife/features/foodsave/merchant/charts/status_donut_chart.dart';
import 'package:proxilife/features/foodsave/merchant/charts/weekly_bar_chart.dart';
import 'package:proxilife/features/foodsave/merchant/merchant_dashboard_screen.dart';
import 'package:proxilife/features/foodsave/merchant/store_setup_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../fakes.dart';

const _store = {
  'id': 1,
  'commercant_id': 7,
  'nom': 'Boulangerie du Lac',
  'adresse': '12 rue du Lac Léman, Tunis',
  'latitude': 36.8323,
  'longitude': 10.2331,
  'categorie': 'boulangerie',
};

/// 7 UTC days ending today, oldest first (same shape as the server).
List<Map<String, dynamic>> _week() {
  final today = DateTime.now().toUtc();
  final base = DateTime.utc(today.year, today.month, today.day);
  const reservations = [2, 0, 5, 1, 3, 0, 4];
  return [
    for (var i = 0; i < 7; i++)
      {
        'date': ChartFormat.dayKey(base.subtract(Duration(days: 6 - i))),
        'reservations': reservations[i],
        'retraits': reservations[i] ~/ 2,
        'revenus_centimes': reservations[i] * 750,
      },
  ];
}

Map<String, dynamic> _stats() => {
      'paniers_actifs': 3,
      'reservations_en_attente': 2,
      'retraits_total': 10,
      'repas_sauves': 14,
      'revenus_centimes': 11250,
      'taux_retrait': 71,
      'par_jour': _week(),
      'par_statut': {'en_attente': 2, 'retire': 10, 'expire': 4, 'annule': 1},
    };

/// Fake server: records requests, never touches the network.
class _FakeServer {
  _FakeServer({this.storeConfigured = true, this.failAll = false});

  bool storeConfigured;
  final bool failAll;
  final List<http.Request> requests = [];

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    if (failAll) return _json({'error': 'Erreur interne du serveur'}, 500);
    final path = request.url.path;
    if (path == '/foodsave/store' && request.method == 'GET') {
      return storeConfigured
          ? _json(_store)
          : _json({'error': 'Commerce non configuré'}, 404);
    }
    if (path == '/foodsave/store' && request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      storeConfigured = true;
      return _json({..._store, ...body});
    }
    if (path == '/foodsave/merchant/stats') return _json(_stats());
    if (path == '/foodsave/geo/reverse') {
      return _json({'adresse': '5 Rue de Rome, Lafayette, Tunis'});
    }
    return _json({'error': 'Introuvable'}, 404);
  });
}

SessionController _session(_FakeServer server) {
  final session = makeTestSession(
    api: ApiClient(httpClient: server.client, baseUrl: 'http://fake'),
  );
  session.user = const UserDto(
    id: 7,
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni@example.com',
    telephone: '+21620000000',
    role: UserRole.commercant,
    statutCompte: AccountStatus.actif,
    soldeCentimes: 0,
  );
  return session;
}

Future<void> _pumpDashboard(WidgetTester tester, _FakeServer server) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MerchantDashboardScreen(session: _session(server)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // Never request real OpenStreetMap tiles from tests.
  setUpAll(() => StoreSetupScreen.debugTileLayerOverride =
      const SizedBox.shrink(key: Key('fake-tiles')));
  tearDownAll(() => StoreSetupScreen.debugTileLayerOverride = null);

  group('ChartFormat', () {
    test('French weekday and day labels from UTC day keys', () {
      // 2026-10-12 is a Monday.
      expect(ChartFormat.weekdayShort('2026-10-12'), 'lun.');
      expect(ChartFormat.weekdayLong('2026-10-18'), 'dimanche');
      expect(ChartFormat.dayLabel('2026-10-12'), 'lundi 12 oct.');
      expect(ChartFormat.dayKey(DateTime.utc(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('compact dinar labels', () {
      expect(ChartFormat.compactDinars(800), '8');
      expect(ChartFormat.compactDinars(1250), '12,5');
      expect(ChartFormat.compactDinars(15075), '151');
      expect(ChartFormat.compactDinars(123456), '1,2 k');
    });

    test('nice axis maximum', () {
      expect(WeeklyBarPainter.niceMax(0), 4);
      expect(WeeklyBarPainter.niceMax(3), 5);
      expect(WeeklyBarPainter.niceMax(7), 10);
      expect(WeeklyBarPainter.niceMax(23), 25);
    });
  });

  testWidgets('dashboard renders greeting, store, KPIs and charts',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final server = _FakeServer();
    await _pumpDashboard(tester, server);

    expect(find.text('Bonjour Ameni'), findsOneWidget);
    expect(find.textContaining('Boulangerie du Lac'), findsOneWidget);
    expect(find.text('Nouveau panier'), findsOneWidget);
    expect(find.text('Scanner un QR'), findsOneWidget);
    expect(find.text('Mes paniers'), findsOneWidget);
    expect(find.text('Configurez votre commerce'), findsNothing);

    // KPI tiles expose their final values to screen readers.
    expect(find.bySemanticsLabel('Paniers actifs : 3'), findsOneWidget);
    expect(find.bySemanticsLabel('À retirer : 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Repas sauvés : 14'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp(r'^Revenus : .*DT')), findsOneWidget);

    expect(find.byType(WeeklyBarChart), findsOneWidget);
    expect(find.byType(StatusDonutChart), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('weekly chart exposes a French textual summary and toggles',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDashboard(tester, _FakeServer());

    final days = _week();
    final first = ChartFormat.weekdayLong(days.first['date'] as String);
    final last = ChartFormat.weekdayLong(days.last['date'] as String);
    expect(
      find.bySemanticsLabel(RegExp(
          '^Réservations des 7 derniers jours : $first 2, .*$last 4\$')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byType(SegmentedButton<WeeklyMetric>));
    await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<WeeklyMetric>),
        matching: find.text('Revenus')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Revenus des 7 derniers jours : ')),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('tapping a bar shows the day tooltip', (tester) async {
    await _pumpDashboard(tester, _FakeServer());
    final chart = find.byType(WeeklyBarChart);
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();

    final rect = tester.getRect(chart);
    final slot = rect.width / 7;
    // Last bar = today.
    await tester.tapAt(Offset(rect.left + slot * 6.5, rect.bottom - 40));
    await tester.pumpAndSettle();

    final today = _week().last['date'] as String;
    expect(find.text(ChartFormat.dayLabel(today)), findsOneWidget);
    expect(find.text('4 réservations'), findsOneWidget);
    expect(find.text('2 retraits'), findsOneWidget);
    expect(find.textContaining('Revenus : '), findsOneWidget);
  });

  testWidgets('donut shows legend with labels, values and pickup rate',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDashboard(tester, _FakeServer());

    final donut = find.byType(StatusDonutChart);
    for (final label in ['Retiré', 'À retirer', 'Expiré', 'Annulé']) {
      expect(find.descendant(of: donut, matching: find.text(label)),
          findsOneWidget);
    }
    expect(find.descendant(of: donut, matching: find.text('10')),
        findsOneWidget);
    expect(find.descendant(of: donut, matching: find.text('4')),
        findsOneWidget);
    expect(
        find.descendant(
            of: donut, matching: find.text(ChartFormat.percent(71))),
        findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(
          r'^Réservations par statut : Retiré 10, À retirer 2, Expiré 4, Annulé 1\. Taux de retrait 71')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('onboarding card when the store is not configured (404)',
      (tester) async {
    final server = _FakeServer(storeConfigured: false);
    await _pumpDashboard(tester, server);

    expect(find.text('Configurez votre commerce'), findsOneWidget);
    expect(find.text('Configurer mon commerce'), findsOneWidget);
    expect(find.byType(WeeklyBarChart), findsNothing);
    expect(find.byType(StatusDonutChart), findsNothing);

    await tester.tap(find.text('Configurer mon commerce'));
    await tester.pumpAndSettle();
    expect(find.byType(StoreSetupScreen), findsOneWidget);
    expect(find.byKey(const Key('fake-tiles')), findsOneWidget);
  });

  testWidgets('friendly error view with retry when the server fails',
      (tester) async {
    await _pumpDashboard(tester, _FakeServer(failAll: true));
    expect(find.text('Erreur interne du serveur'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  group('StoreSetupScreen', () {
    Future<void> pumpSetup(WidgetTester tester, _FakeServer server,
        {StoreDto? initial, List<Object?>? popped}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final session = _session(server);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<StoreDto>(
                    MaterialPageRoute(
                      builder: (_) => StoreSetupScreen(
                        session: session,
                        initial: initial,
                        tileLayer: const SizedBox.shrink(),
                      ),
                    ),
                  );
                  popped?.add(r);
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates fields and position in French', (tester) async {
      final server = _FakeServer(storeConfigured: false);
      await pumpSetup(tester, server);

      expect(find.text('Configurer le commerce'), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsOneWidget);
      final save = find.text('Enregistrer mon commerce');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
          find.text('Saisissez le nom du commerce (2 caractères minimum).'),
          findsOneWidget);
      expect(find.text('Saisissez l\'adresse complète du commerce.'),
          findsOneWidget);
      expect(
          find.text(
              'Placez votre commerce sur la carte ou utilisez votre position.'),
          findsOneWidget);
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('saves an existing store and pops the StoreDto',
        (tester) async {
      final server = _FakeServer();
      final popped = <Object?>[];
      await pumpSetup(tester, server,
          initial: StoreDto.fromJson(_store), popped: popped);

      expect(find.text('Modifier le commerce'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Boulangerie du Lac'),
          'Pâtisserie Ameni');
      final save = find.text('Enregistrer les modifications');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final put = server.requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['nom'], 'Pâtisserie Ameni');
      expect(body['categorie'], 'boulangerie');
      expect(body['latitude'], 36.8323);
      expect(popped.single, isA<StoreDto>());
      expect((popped.single! as StoreDto).nom, 'Pâtisserie Ameni');
    });

    testWidgets('moving the marker replaces the address, both are saved',
        (tester) async {
      final server = _FakeServer();
      await pumpSetup(tester, server, initial: StoreDto.fromJson(_store));

      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)) +
          const Offset(60, 40));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final reverse = server.requests
          .singleWhere((r) => r.url.path == '/foodsave/geo/reverse');
      expect(reverse.url.queryParameters['lat'], isNot('36.8323'));
      expect(find.widgetWithText(TextFormField, '5 Rue de Rome, Lafayette, Tunis'),
          findsOneWidget);
      expect(find.textContaining('Adresse mise à jour depuis la carte'),
          findsOneWidget);

      final save = find.text('Enregistrer les modifications');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final body = jsonDecode(
              server.requests.singleWhere((r) => r.method == 'PUT').body)
          as Map<String, dynamic>;
      expect(body['adresse'], '5 Rue de Rome, Lafayette, Tunis');
      expect(body['latitude'], isNot(36.8323));
    });
  });
}
