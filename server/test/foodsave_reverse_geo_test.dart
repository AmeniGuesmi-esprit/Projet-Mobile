import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/reverse_geocoder.dart';
import 'package:proxilife_server/src/foodsave/services/route_planner.dart';
import 'package:proxilife_server/src/repositories/payment_method_repository.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/services/payment_service.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _NoEmail implements EmailSender {
  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {}
}

class _FakePlanner implements RoutePlanner {
  final List<TravelMode> modes = [];
  bool unavailable = false;

  @override
  Future<RouteDto?> route({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required TravelMode mode,
  }) async {
    modes.add(mode);
    if (unavailable) return null;
    return RouteDto(
      mode: mode,
      distanceMetres: mode == TravelMode.voiture ? 5295 : 4644,
      dureeSecondes: mode == TravelMode.voiture ? 397 : 3714,
      points: [(fromLatitude, fromLongitude), (toLatitude, toLongitude)],
    );
  }
}

class _FakeGeocoder implements ReverseGeocoder {
  final List<(double, double)> calls = [];
  String? answer = '12 Rue de Marseille, Lafayette, Tunis';

  @override
  Future<String?> reverse(double latitude, double longitude) async {
    calls.add((latitude, longitude));
    return answer;
  }
}

void main() {
  group('formatNominatimAddress', () {
    test('number + road, neighbourhood, city', () {
      expect(
          formatNominatimAddress({
            'address': {
              'house_number': '12',
              'road': 'Rue de Marseille',
              'suburb': 'Lafayette',
              'city': 'Tunis',
              'country': 'Tunisie',
            },
          }),
          '12 Rue de Marseille, Lafayette, Tunis');
    });

    test('no road → neighbourhood + city', () {
      expect(
          formatNominatimAddress({
            'address': {
              'suburb': 'Cite Des Martyrs',
              'city_district': 'Délégation Essijoumi',
              'city': 'Tunis',
            },
          }),
          'Cite Des Martyrs, Tunis');
    });

    test('only display_name → its first parts; nothing → null', () {
      expect(
          formatNominatimAddress(
              {'display_name': 'A, B, C, D, Tunisie', 'address': {}}),
          'A, B, C');
      expect(formatNominatimAddress({'error': 'Unable to geocode'}), isNull);
    });
  });

  group('parseOsrmRoute', () {
    test('GeoJSON [lng, lat] becomes (lat, lng); distance and duration', () {
      final route = parseOsrmRoute({
        'code': 'Ok',
        'routes': [
          {
            'distance': 5295.4,
            'duration': 396.6,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [10.1814, 36.8064],
                [10.1718, 36.7751],
              ],
            },
          },
        ],
      }, TravelMode.voiture)!;
      expect(route.mode, TravelMode.voiture);
      expect(route.distanceMetres, 5295);
      expect(route.dureeSecondes, 397);
      expect(route.points, [(36.8064, 10.1814), (36.7751, 10.1718)]);
    });

    test('no route / malformed answer → null', () {
      expect(parseOsrmRoute({'code': 'NoRoute'}, TravelMode.pied), isNull);
      expect(
          parseOsrmRoute({'code': 'Ok', 'routes': []}, TravelMode.pied),
          isNull);
      expect(
          parseOsrmRoute({
            'code': 'Ok',
            'routes': [
              {'distance': 1, 'duration': 1, 'geometry': {}},
            ],
          }, TravelMode.pied),
          isNull);
    });
  });

  group('GET /foodsave/geo/reverse', () {
    late AppDatabase database;
    late _FakeGeocoder geocoder;
    late _FakePlanner planner;
    late Handler handler;
    late String token;

    setUp(() async {
      database = await AppDatabase.inMemory();
      final db = database.db;
      final hasFoodSave = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'panier'");
      if (hasFoodSave.isEmpty) await createFoodSaveSchema(db);
      final users = UserRepository(db);
      geocoder = _FakeGeocoder();
      planner = _FakePlanner();
      handler = buildApp(
        database,
        const ServerConfig(
          smtpHost: '',
          smtpPort: 0,
          smtpUser: '',
          smtpPass: '',
          emailConsoleMode: true,
          dbPath: ':memory:',
          port: 0,
        ),
        emailSender: _NoEmail(),
        logRequestsMiddleware: false,
        foodSave: FoodSaveContext(
          db: db,
          users: users,
          payments: PaymentService(
            db: db,
            users: users,
            methods: PaymentMethodRepository(db),
            transactions: TransactionRepository(db),
          ),
          uploadsDir: 'build/test_uploads',
          geocoder: geocoder,
          routePlanner: planner,
        ),
      );
      final id = await db.insert('utilisateur', {
        'nom': 'Guesmi',
        'prenom': 'Ameni',
        'email': 'commerce@test.fr',
        'telephone': '0612345678',
        'mot_de_passe_hash': 'x',
        'role': 'commercant',
        'statut_compte': 'actif',
        'rib': '30004000011234567890173',
        'solde_centimes': 0,
        'cree_le': DateTime.now().toIso8601String(),
      });
      token = await SessionService(db, users).createSession(id);
    });

    tearDown(() async => database.close());

    Future<(int, Map<String, dynamic>)> get(String query,
        {bool auth = true, String path = 'reverse'}) async {
      final response = await handler(Request(
          'GET', Uri.parse('http://test/foodsave/geo/$path?$query'),
          headers: {if (auth) 'authorization': 'Bearer $token'}));
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, dynamic>,
      );
    }

    test('returns the address of the position', () async {
      final (status, body) = await get('lat=36.8008&lng=10.18');
      expect(status, 200);
      expect(body['adresse'], '12 Rue de Marseille, Lafayette, Tunis');
      expect(geocoder.calls.single, (36.8008, 10.18));
    });

    test('invalid coordinates → 400, unknown place → 404, no auth → 401',
        () async {
      expect((await get('lat=95&lng=10')).$1, 400);
      expect((await get('lat=abc&lng=10')).$1, 400);
      expect(geocoder.calls, isEmpty);
      geocoder.answer = null;
      final (status, body) = await get('lat=36.8&lng=10.18');
      expect(status, 404);
      expect(body['error'], contains('Aucune adresse'));
      expect((await get('lat=36.8&lng=10.18', auth: false)).$1, 401);
    });

    const trip = 'from_lat=36.8064&from_lng=10.1814&to_lat=36.7751&to_lng=10.1718';

    test('route by car (default) and on foot', () async {
      final (status, body) = await get(trip, path: 'route');
      expect(status, 200, reason: '$body');
      final car = RouteDto.fromJson(body);
      expect(car.mode, TravelMode.voiture);
      expect(car.distanceMetres, 5295);
      expect(car.points.first, (36.8064, 10.1814));

      final (_, walkBody) = await get('$trip&mode=pied', path: 'route');
      expect(RouteDto.fromJson(walkBody).dureeSecondes, 3714);
      expect(planner.modes, [TravelMode.voiture, TravelMode.pied]);
    });

    test('route: bad input → 400, too far → 400, no route → 503', () async {
      expect((await get('$trip&mode=velo', path: 'route')).$1, 400);
      expect((await get('from_lat=36.8&from_lng=10.18', path: 'route')).$1,
          400);
      final (far, farBody) = await get(
          'from_lat=36.8&from_lng=10.18&to_lat=48.85&to_lng=2.35',
          path: 'route');
      expect(far, 400);
      expect(farBody['error'], contains('trop loin'));
      expect(planner.modes, isEmpty);
      planner.unavailable = true;
      expect((await get(trip, path: 'route')).$1, 503);
      expect((await get(trip, path: 'route', auth: false)).$1, 401);
    });
  });
}
