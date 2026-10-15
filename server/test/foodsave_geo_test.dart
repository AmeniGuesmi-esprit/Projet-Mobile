import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/nearby_notification_service.dart';
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

/// Store position (Tunis centre).
const storeLat = 36.8065;
const storeLng = 10.1815;

/// Degrees of latitude for [km] going north (haversine Earth radius).
double _northDeg(double km) => km / 6371.0088 * 180 / 3.141592653589793;

class _Harness {
  _Harness(this.database, this.ctx, this.handler, this.sessions);

  final AppDatabase database;
  final FoodSaveContext ctx;
  final Handler handler;
  final SessionService sessions;
  int _seq = 0;

  static final fixedNow = DateTime.utc(2026, 10, 13, 10);

  static Future<_Harness> create() async {
    final database = await AppDatabase.inMemory();
    final db = database.db;
    // Work around: AppDatabase.onCreate may not create the FoodSave tables
    // on a fresh database (only onUpgrade does).
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'panier'");
    if (tables.isEmpty) await createFoodSaveSchema(db);
    final users = UserRepository(db);
    final ctx = FoodSaveContext(
      db: db,
      users: users,
      payments: PaymentService(
        db: db,
        users: users,
        methods: PaymentMethodRepository(db),
        transactions: TransactionRepository(db),
      ),
      uploadsDir: 'uploads_test',
      clock: () => fixedNow,
    );
    final handler = buildApp(
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
      foodSave: ctx,
    );
    return _Harness(database, ctx, handler, SessionService(db, users));
  }

  Future<int> insertUser({
    String role = 'client',
    String statut = 'actif',
  }) async {
    _seq++;
    return database.db.insert('utilisateur', {
      'nom': 'Test',
      'prenom': 'User$_seq',
      'email': 'user$_seq@example.com',
      'telephone': '0612345678',
      'mot_de_passe_hash': 'x',
      'role': role,
      'statut_compte': statut,
      'cree_le': fixedNow.toIso8601String(),
    });
  }

  Future<void> setLocation(int userId, double lat, double lng) =>
      database.db.insert('localisation_client', {
        'utilisateur_id': userId,
        'latitude': lat,
        'longitude': lng,
        'mis_a_jour_le': fixedNow.toIso8601String(),
      });

  Future<int> insertStoreAndBasket(int merchantId,
      {String statut = 'disponible', int quantite = 3}) async {
    final now = fixedNow.toIso8601String();
    await database.db.insert('commerce', {
      'commercant_id': merchantId,
      'nom': 'Boulangerie du Lac',
      'adresse': '1 rue du Lac, Tunis',
      'latitude': storeLat,
      'longitude': storeLng,
      'categorie': FoodCategory.values.first.apiValue,
      'cree_le': now,
      'mis_a_jour_le': now,
    });
    return insertBasket(merchantId, statut: statut, quantite: quantite);
  }

  Future<int> insertBasket(int merchantId,
      {String statut = 'disponible', int quantite = 3}) {
    final now = fixedNow.toIso8601String();
    return database.db.insert('panier', {
      'titre': 'Panier du soir',
      'contenu': 'Pains et viennoiseries',
      'categorie': FoodCategory.values.first.apiValue,
      'prix_centimes': 500,
      'prix_initial_centimes': 1500,
      'quantite': quantite,
      'quantite_initiale': 3,
      'creneau_retrait_debut':
          fixedNow.add(const Duration(hours: 1)).toIso8601String(),
      'creneau_retrait_fin':
          fixedNow.add(const Duration(hours: 3)).toIso8601String(),
      'date_expiration':
          fixedNow.add(const Duration(hours: 4)).toIso8601String(),
      'statut': statut,
      'commercant_id': merchantId,
      'cree_le': now,
      'mis_a_jour_le': now,
    });
  }

  Future<List<int>> notifiedUsers(int basketId) async {
    final rows = await database.db.query('foodsave_notification',
        columns: ['utilisateur_id'],
        where: 'panier_id = ?',
        whereArgs: [basketId],
        orderBy: 'utilisateur_id');
    return rows.map((r) => r['utilisateur_id'] as int).toList();
  }

  Future<(int, Map<String, dynamic>)> call(String verb, String path,
      {Object? body, String? token}) async {
    final response = await handler(Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    ));
    final raw = await response.readAsString();
    return (
      response.statusCode,
      raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}

void main() {
  late _Harness h;

  setUp(() async {
    h = await _Harness.create();
  });

  tearDown(() async {
    await h.database.close();
  });

  group('location', () {
    late String token;

    setUp(() async {
      token = await h.sessions.createSession(await h.insertUser());
    });

    test('GET is 404 before any position', () async {
      final (status, body) =
          await h.call('GET', '/foodsave/location', token: token);
      expect(status, 404);
      expect(body['error'], isA<String>());
    });

    test('PUT rejects invalid coordinates and null island', () async {
      for (final bad in [
        {'latitude': 91, 'longitude': 10},
        {'latitude': 36.8, 'longitude': -180.5},
        {'latitude': 0, 'longitude': 0},
        {'latitude': '36.8', 'longitude': 10.1},
        {'latitude': 36.8},
      ]) {
        final (status, body) =
            await h.call('PUT', '/foodsave/location', body: bad, token: token);
        expect(status, 400, reason: '$bad');
        expect(body['error'], isA<String>());
      }
      final (malformed, _) = await h.call('PUT', '/foodsave/location',
          body: 'not json', token: token);
      expect(malformed, 400);
      final (status, _) =
          await h.call('GET', '/foodsave/location', token: token);
      expect(status, 404);
    });

    test('PUT upserts, GET returns it, DELETE forgets it', () async {
      var (status, body) = await h.call('PUT', '/foodsave/location',
          body: {'latitude': 36.8, 'longitude': 10}, token: token);
      expect(status, 200);
      expect(body['message'], isA<String>());

      (status, body) = await h.call('PUT', '/foodsave/location',
          body: {'latitude': 36.81, 'longitude': 10.18}, token: token);
      expect(status, 200);

      (status, body) = await h.call('GET', '/foodsave/location', token: token);
      expect(status, 200);
      expect(body['latitude'], 36.81);
      expect(body['longitude'], 10.18);
      expect(body['mis_a_jour_le'], _Harness.fixedNow.toIso8601String());
      final count = await h.database.db.query('localisation_client');
      expect(count, hasLength(1));

      (status, body) =
          await h.call('DELETE', '/foodsave/location', token: token);
      expect(status, 204);
      (status, body) = await h.call('GET', '/foodsave/location', token: token);
      expect(status, 404);
      // Deleting twice is harmless.
      (status, body) =
          await h.call('DELETE', '/foodsave/location', token: token);
      expect(status, 204);
    });

    test('requires authentication', () async {
      final (status, _) = await h.call('GET', '/foodsave/location');
      expect(status, 401);
    });
  });

  group('notifyNearbyClients', () {
    late int merchant;
    late int basket;
    late FoodSaveNearbyNotificationService service;

    setUp(() async {
      merchant = await h.insertUser(role: 'commercant');
      basket = await h.insertStoreAndBasket(merchant);
      service = FoodSaveNearbyNotificationService(h.ctx);
    });

    test('notifies only active clients within 5 km, exactly once', () async {
      final at06 = await h.insertUser();
      await h.setLocation(at06, storeLat + _northDeg(0.6), storeLng);
      // 4.9 km due east (longitude scaled by cos(lat)).
      final at49 = await h.insertUser();
      final cosLat = 0.8008; // cos(36.8065°)
      await h.setLocation(at49, storeLat, storeLng + _northDeg(4.9) / cosLat);
      // 4.99 km north: inside the radius, near the bounding-box edge.
      final at499 = await h.insertUser();
      await h.setLocation(at499, storeLat - _northDeg(4.99), storeLng);
      final at52 = await h.insertUser();
      await h.setLocation(at52, storeLat + _northDeg(5.2), storeLng);
      // Diagonal corner of the box: inside the box, outside the circle.
      final corner = await h.insertUser();
      await h.setLocation(corner, storeLat + _northDeg(4),
          storeLng + _northDeg(4) / cosLat);
      final noLocation = await h.insertUser();
      final driver = await h.insertUser(role: 'conducteur');
      await h.setLocation(driver, storeLat, storeLng + 0.001);
      final otherMerchant = await h.insertUser(role: 'commercant');
      await h.setLocation(otherMerchant, storeLat, storeLng + 0.001);
      final suspended = await h.insertUser(statut: 'suspendu');
      await h.setLocation(suspended, storeLat, storeLng + 0.001);
      final unverified = await h.insertUser(statut: 'en_attente_verification');
      await h.setLocation(unverified, storeLat, storeLng + 0.001);
      await h.setLocation(merchant, storeLat, storeLng);

      // Sanity check of the fixtures with the shared haversine.
      expect(haversineKm(storeLat, storeLng, storeLat,
          storeLng + _northDeg(4.9) / cosLat), closeTo(4.9, 0.01));
      expect(
          haversineKm(storeLat, storeLng, storeLat + _northDeg(4),
              storeLng + _northDeg(4) / cosLat),
          greaterThan(5));

      final created = await service.notifyNearbyClients(basket);
      expect(created, 3);
      expect(await h.notifiedUsers(basket), [at06, at49, at499]);
      for (final excluded in [at52, corner, noLocation, driver,
          otherMerchant, suspended, unverified, merchant]) {
        expect(await h.notifiedUsers(basket), isNot(contains(excluded)));
      }

      final row = (await h.database.db.query('foodsave_notification',
              where: 'utilisateur_id = ?', whereArgs: [at06]))
          .single;
      expect(row['type'], FoodSaveNotificationType.nouveauPanier.apiValue);
      expect(row['titre'], '🍱 Nouveau panier anti-gaspillage !');
      expect(row['message'] as String,
          startsWith('Un panier est disponible près de chez vous'));
      expect(row['message'] as String, contains('Boulangerie du Lac'));
      expect(row['cle_evenement'], 'nouveau_panier:$basket:user:$at06');
      expect(row['lu'], 0);

      final journal = await h.database.db.query('foodsave_journal',
          where: 'evenement = ?', whereArgs: ['notifications_envoyees']);
      expect(journal, hasLength(1));
      expect(jsonDecode(journal.single['details'] as String)['nouvelles'], 3);

      // Second call: no duplicates.
      expect(await service.notifyNearbyClients(basket), 0);
      expect(await h.notifiedUsers(basket), hasLength(3));
    });

    test('a client who moves into the radius later is notified once',
        () async {
      final client = await h.insertUser();
      await h.setLocation(client, storeLat + _northDeg(8), storeLng);
      expect(await service.notifyNearbyClients(basket), 0);
      await h.database.db.update(
          'localisation_client', {'latitude': storeLat + _northDeg(1)},
          where: 'utilisateur_id = ?', whereArgs: [client]);
      expect(await service.notifyNearbyClients(basket), 1);
      expect(await service.notifyNearbyClients(basket), 0);
    });

    test('baskets that are not on sale notify nobody', () async {
      final client = await h.insertUser();
      await h.setLocation(client, storeLat, storeLng + 0.001);
      for (final statut in ['epuise', 'expire', 'annule']) {
        final id = await h.insertBasket(merchant, statut: statut);
        expect(await service.notifyNearbyClients(id), 0, reason: statut);
      }
      final empty = await h.insertBasket(merchant, quantite: 0);
      expect(await service.notifyNearbyClients(empty), 0);
      expect(await service.notifyNearbyClients(999999), 0);
      expect(await h.database.db.query('foodsave_notification'), isEmpty);
    });
  });

  group('GeoBoundingBox', () {
    test('wraps around the antimeridian', () {
      final box = GeoBoundingBox.around(-17.7, 179.99, 5);
      expect(box.sqlWhere('a', 'b'), contains('OR'));
      expect(box.sqlArgs[3] as double, lessThan(-179.9));
    });

    test('covers every longitude at the poles', () {
      final box = GeoBoundingBox.around(89.99, 10, 5);
      expect(box.allLongitudes, isTrue);
      expect(box.sqlArgs, hasLength(2));
    });

    test('formats distances in French', () {
      expect(formatDistanceFr(0.6), '600 m');
      expect(formatDistanceFr(4.93), '4,9 km');
    });
  });

  group('notifications', () {
    late int alice;
    late int bob;
    late String aliceToken;
    late String bobToken;

    Future<void> notify(int userId, String key, {int minutes = 0}) async {
      await h.database.db.insert('foodsave_notification', {
        'utilisateur_id': userId,
        'type': FoodSaveNotificationType.reservationConfirmee.apiValue,
        'titre': 'Titre $key',
        'message': 'Message $key',
        'cle_evenement': key,
        'lu': 0,
        'cree_le': _Harness.fixedNow
            .add(Duration(minutes: minutes))
            .toIso8601String(),
      });
    }

    setUp(() async {
      alice = await h.insertUser();
      bob = await h.insertUser();
      aliceToken = await h.sessions.createSession(alice);
      bobToken = await h.sessions.createSession(bob);
      await notify(alice, 'a1', minutes: 1);
      await notify(alice, 'a2', minutes: 3);
      await notify(alice, 'a3', minutes: 2);
      await notify(bob, 'b1', minutes: 5);
    });

    Future<List<Map<String, dynamic>>> list(String token,
        {bool unread = false}) async {
      final (status, body) = await h.call(
          'GET', '/foodsave/notifications${unread ? '?non_lues=1' : ''}',
          token: token);
      expect(status, 200);
      return (body['items'] as List).cast<Map<String, dynamic>>();
    }

    test('lists own notifications newest first as DTOs', () async {
      final items = await list(aliceToken);
      expect(items.map((n) => n['titre']), ['Titre a2', 'Titre a3', 'Titre a1']);
      final dto = FoodSaveNotificationDto.fromJson(items.first);
      expect(dto.lu, isFalse);
      expect(dto.type, FoodSaveNotificationType.reservationConfirmee);
      expect(dto.creeLe, _Harness.fixedNow.add(const Duration(minutes: 3)));
      expect((await list(bobToken)).single['titre'], 'Titre b1');
    });

    test('mark one as read, unread filter, ownership', () async {
      final items = await list(aliceToken);
      final firstId = items.first['id'] as int;
      final bobId = (await list(bobToken)).single['id'] as int;

      var (status, _) = await h.call(
          'POST', '/foodsave/notifications/$firstId/read',
          token: aliceToken);
      expect(status, 200);
      // Idempotent.
      (status, _) = await h.call(
          'POST', '/foodsave/notifications/$firstId/read',
          token: aliceToken);
      expect(status, 200);

      final unread = await list(aliceToken, unread: true);
      expect(unread.map((n) => n['titre']), ['Titre a3', 'Titre a1']);
      expect((await list(aliceToken)).first['lu'], isTrue);

      // Bob cannot touch Alice's notification and vice versa.
      (status, _) = await h.call(
          'POST', '/foodsave/notifications/$firstId/read',
          token: bobToken);
      expect(status, 404);
      (status, _) = await h.call('POST', '/foodsave/notifications/$bobId/read',
          token: aliceToken);
      expect(status, 404);
      (status, _) = await h.call('POST', '/foodsave/notifications/424242/read',
          token: aliceToken);
      expect(status, 404);
      expect((await list(bobToken, unread: true)), hasLength(1));
    });

    test('read-all only affects the caller', () async {
      final (status, body) = await h.call(
          'POST', '/foodsave/notifications/read-all',
          token: aliceToken);
      expect(status, 200);
      expect(body['message'], isA<String>());
      expect(await list(aliceToken, unread: true), isEmpty);
      expect(await list(aliceToken), hasLength(3));
      expect(await list(bobToken, unread: true), hasLength(1));
    });

    test('caps the list at 100 items', () async {
      for (var i = 0; i < 105; i++) {
        await notify(bob, 'bulk$i', minutes: 10 + i);
      }
      final items = await list(bobToken);
      expect(items, hasLength(100));
      expect(items.first['titre'], 'Titre bulk104');
    });
  });
}
