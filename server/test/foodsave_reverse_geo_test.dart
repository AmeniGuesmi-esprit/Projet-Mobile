import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/reverse_geocoder.dart';
import 'package:proxilife_server/src/repositories/payment_method_repository.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/services/payment_service.dart';
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

  group('GET /foodsave/geo/reverse', () {
    late AppDatabase database;
    late _FakeGeocoder geocoder;
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
        {bool auth = true}) async {
      final response = await handler(Request(
          'GET', Uri.parse('http://test/foodsave/geo/reverse?$query'),
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
  });
}
