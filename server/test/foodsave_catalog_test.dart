import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/basket_service.dart';
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

/// In-memory server with an injectable FoodSave clock.
class CatalogTestServer {
  CatalogTestServer._(this.handler, this.db, this.ctx, this.uploads,
      this._sessions);

  final Handler handler;
  final AppDatabase db;
  final FoodSaveContext ctx;
  final Directory uploads;
  final SessionService _sessions;

  /// Fake "now" used by every FoodSave service.
  static DateTime clock = DateTime.utc(2030, 3, 10, 9);

  static Future<CatalogTestServer> create() async {
    clock = DateTime.utc(2030, 3, 10, 9);
    final db = await AppDatabase.inMemory();
    // Workaround: older foundation versions only created the FoodSave tables
    // on upgrade (v1 -> v2), not on a fresh database.
    final hasFoodSave = (await db.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'commerce'"))
        .isNotEmpty;
    if (!hasFoodSave) await createFoodSaveSchema(db.db);
    final uploads = Directory.systemTemp.createTempSync('fs_catalog_');
    final users = UserRepository(db.db);
    final ctx = FoodSaveContext(
      db: db.db,
      users: users,
      payments: PaymentService(
        db: db.db,
        users: users,
        methods: PaymentMethodRepository(db.db),
        transactions: TransactionRepository(db.db),
      ),
      uploadsDir: uploads.path,
      clock: () => clock,
    );
    final handler = buildApp(
      db,
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
    return CatalogTestServer._(
        handler, db, ctx, uploads, SessionService(db.db, users));
  }

  Future<void> close() async {
    await db.close();
    if (uploads.existsSync()) uploads.deleteSync(recursive: true);
  }

  var _userSeq = 0;

  /// Creates an active user directly (no slow password hashing) and returns
  /// (token, id).
  Future<(String, int)> user(String role) async {
    _userSeq++;
    final id = await db.db.insert('utilisateur', {
      'nom': 'Guesmi',
      'prenom': 'Ameni',
      'email': '$role$_userSeq@test.fr',
      'telephone': '0612345678',
      'mot_de_passe_hash': 'x',
      'role': role,
      'statut_compte': 'actif',
      'solde_centimes': 0,
      'cree_le': DateTime.now().toUtc().toIso8601String(),
    });
    return (await _sessions.createSession(id), id);
  }

  Future<void> setLocation(int userId, double lat, double lng) =>
      db.db.insert('localisation_client', {
        'utilisateur_id': userId,
        'latitude': lat,
        'longitude': lng,
        'mis_a_jour_le': clock.toIso8601String(),
      });

  Future<(int, Map<String, dynamic>)> call(
    String verb,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final response = await handler(Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : jsonEncode(body),
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

  Future<Response> raw(String verb, String path,
          {required String token, List<int>? bytes, String? contentType}) async =>
      handler(Request(
        verb,
        Uri.parse('http://test$path'),
        body: bytes,
        headers: {
          'authorization': 'Bearer $token',
          if (contentType != null) 'content-type': contentType,
        },
      ));

  // ---------------------------------------------------------------- helpers

  Future<Map<String, dynamic>> setupStore(String token,
      {double lat = 36.8008,
      double lng = 10.18,
      String nom = 'Boulangerie Ameni'}) async {
    final (status, body) = await call('PUT', '/foodsave/store',
        token: token,
        body: {
          'nom': nom,
          'adresse': 'Avenue Habib Bourguiba, Tunis',
          'latitude': lat,
          'longitude': lng,
          'categorie': 'boulangerie',
        });
    expect(status, 200, reason: body.toString());
    return body;
  }

  Map<String, dynamic> basketBody([Map<String, dynamic> overrides = const {}]) =>
      {
        'titre': 'Panier du soir',
        'contenu': 'Pains et viennoiseries du jour',
        'categorie': 'boulangerie',
        'prix_centimes': 500,
        'prix_initial_centimes': 1500,
        'quantite': 3,
        'creneau_retrait_debut': iso(clock.add(const Duration(hours: 1))),
        'creneau_retrait_fin': iso(clock.add(const Duration(hours: 3))),
        'date_expiration': iso(clock.add(const Duration(hours: 5))),
        ...overrides,
      };

  Future<Map<String, dynamic>> createBasket(String token,
      [Map<String, dynamic> overrides = const {}]) async {
    final (status, body) = await call('POST', '/foodsave/merchant/baskets',
        token: token, body: basketBody(overrides));
    expect(status, 201, reason: body.toString());
    return body['panier'] as Map<String, dynamic>;
  }

  Future<void> insertReservation({
    required int basketId,
    required int clientId,
    required String statut,
    String statutPaiement = 'paye',
    int quantite = 1,
    int montant = 500,
    required DateTime date,
    DateTime? retireLe,
  }) =>
      db.db.insert('reservation', {
        'date': iso(date),
        'statut': statut,
        'panier_id': basketId,
        'client_id': clientId,
        'quantite_reservee': quantite,
        'montant_centimes': montant,
        'statut_paiement': statutPaiement,
        'retire_le': retireLe == null ? null : iso(retireLe),
        'cree_le': iso(date),
      });
}

String iso(DateTime d) => d.toUtc().toIso8601String();

final Uint8List pngBytes = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 6]);
final Uint8List jpegBytes =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70]);

List<String> titles(Map<String, dynamic> body) => (body['items'] as List)
    .map((e) => (e as Map<String, dynamic>)['titre'] as String)
    .toList();

void main() {
  late CatalogTestServer ts;

  setUp(() async {
    ts = await CatalogTestServer.create();
  });

  tearDown(() async {
    await ts.close();
  });

  group('store', () {
    test('GET 404 before setup, PUT validates and upserts', () async {
      final (token, merchantId) = await ts.user('commercant');

      var res = await ts.call('GET', '/foodsave/store', token: token);
      expect(res.$1, 404);
      expect(res.$2['error'], 'Commerce non configuré');

      final valid = {
        'nom': 'Boulangerie Ameni',
        'adresse': 'Avenue Habib Bourguiba, Tunis',
        'latitude': 36.8008,
        'longitude': 10.18,
        'categorie': 'boulangerie',
      };
      for (final bad in <Map<String, dynamic>>[
        {...valid, 'latitude': 91},
        {...valid, 'latitude': 0, 'longitude': 0},
        {...valid, 'nom': 'A'},
        {...valid, 'nom': 'x' * 81},
        {...valid, 'categorie': 'inconnue'},
        {...valid, 'latitude': 'abc'},
        {...valid}..remove('adresse'),
      ]) {
        res = await ts.call('PUT', '/foodsave/store', token: token, body: bad);
        expect(res.$1, 400, reason: bad.toString());
        expect(res.$2['error'], isA<String>());
      }

      res = await ts.call('PUT', '/foodsave/store', token: token, body: valid);
      expect(res.$1, 200);
      expect(res.$2['commercant_id'], merchantId);
      final storeId = res.$2['id'];

      res = await ts.call('PUT', '/foodsave/store',
          token: token, body: {...valid, 'nom': 'Chez Ameni'});
      expect(res.$1, 200);
      expect(res.$2['id'], storeId);
      expect(res.$2['nom'], 'Chez Ameni');

      res = await ts.call('GET', '/foodsave/store', token: token);
      expect(res.$1, 200);
      expect(res.$2['nom'], 'Chez Ameni');
      expect(res.$2['categorie'], 'boulangerie');
    });

    test('non-merchant gets 403 on merchant routes', () async {
      final (token, _) = await ts.user('client');
      for (final (verb, path) in [
        ('GET', '/foodsave/store'),
        ('GET', '/foodsave/merchant/baskets'),
        ('GET', '/foodsave/merchant/stats'),
        ('GET', '/foodsave/merchant/baskets/1'),
      ]) {
        final res = await ts.call(verb, path, token: token);
        expect(res.$1, 403, reason: path);
      }
      final res = await ts.call('POST', '/foodsave/merchant/baskets',
          token: token, body: ts.basketBody());
      expect(res.$1, 403);
    });
  });

  group('merchant baskets', () {
    test('creation requires a store and validates fields', () async {
      final (token, _) = await ts.user('commercant');

      var res = await ts.call('POST', '/foodsave/merchant/baskets',
          token: token, body: ts.basketBody());
      expect(res.$1, 409);

      await ts.setupStore(token);
      for (final bad in <Map<String, dynamic>>[
        {'prix_initial_centimes': 500},
        {'prix_initial_centimes': 400},
        {'quantite': -1},
        {'quantite': 0},
        {'prix_centimes': 0},
        {'prix_centimes': 4.5},
        {'titre': 'ab'},
        {'titre': null},
        {
          'creneau_retrait_debut':
              iso(CatalogTestServer.clock.subtract(const Duration(hours: 3))),
          'creneau_retrait_fin':
              iso(CatalogTestServer.clock.subtract(const Duration(hours: 1))),
        },
        {
          'date_expiration':
              iso(CatalogTestServer.clock.add(const Duration(hours: 2))),
        },
        {'creneau_retrait_fin': 'pas une date'},
      ]) {
        res = await ts.call('POST', '/foodsave/merchant/baskets',
            token: token, body: ts.basketBody(bad));
        expect(res.$1, 400, reason: bad.toString());
      }

      res = await ts.call('POST', '/foodsave/merchant/baskets',
          token: token, body: ts.basketBody());
      expect(res.$1, 201);
      expect(res.$2['clients_notifies'], isA<int>());
      final panier = res.$2['panier'] as Map<String, dynamic>;
      expect(panier['statut'], 'disponible');
      expect(panier['quantite'], 3);
      expect(panier['quantite_initiale'], 3);
      expect(panier['reservations_actives'], 0);
      expect(panier['commerce']['nom'], 'Boulangerie Ameni');
      expect((panier['creneau_retrait_fin'] as String).endsWith('Z'), isTrue);

      res = await ts.call('GET', '/foodsave/merchant/baskets', token: token);
      expect(res.$1, 200);
      expect((res.$2['items'] as List), hasLength(1));
      res = await ts.call('GET', '/foodsave/merchant/baskets?statut=epuise',
          token: token);
      expect((res.$2['items'] as List), isEmpty);
      res = await ts.call('GET', '/foodsave/merchant/baskets?statut=nope',
          token: token);
      expect(res.$1, 400);
    });

    test('another merchant gets 404 on someone else\'s basket', () async {
      final (owner, _) = await ts.user('commercant');
      final (other, _) = await ts.user('commercant');
      await ts.setupStore(owner);
      await ts.setupStore(other, nom: 'Autre commerce');
      final id = (await ts.createBasket(owner))['id'];

      final path = '/foodsave/merchant/baskets/$id';
      expect((await ts.call('GET', path, token: other)).$1, 404);
      expect(
          (await ts.call('PATCH', path, token: other, body: {'quantite': 1}))
              .$1,
          404);
      expect((await ts.call('POST', '$path/cancel', token: other)).$1, 404);
      expect((await ts.call('DELETE', path, token: other)).$1, 404);
      final img = await ts.raw('POST', '$path/image',
          token: other, bytes: pngBytes, contentType: 'image/png');
      expect(img.statusCode, 404);
      // Still intact for the owner.
      final res = await ts.call('GET', path, token: owner);
      expect(res.$1, 200);
      expect(res.$2['statut'], 'disponible');
    });

    test('PATCH quantity rules and epuise/disponible transitions', () async {
      final (token, _) = await ts.user('commercant');
      await ts.setupStore(token);
      final id = (await ts.createBasket(token, {'quantite': 3}))['id'];
      final path = '/foodsave/merchant/baskets/$id';

      var res =
          await ts.call('PATCH', path, token: token, body: {'quantite': 0});
      expect(res.$1, 200);
      expect(res.$2['statut'], 'epuise');
      expect(res.$2['quantite'], 0);
      expect(res.$2['quantite_initiale'], 3);

      res = await ts.call('PATCH', path, token: token, body: {'quantite': 5});
      expect(res.$1, 200);
      expect(res.$2['statut'], 'disponible');
      expect(res.$2['quantite'], 5);
      expect(res.$2['quantite_initiale'], 8); // 3 + (5 - 0)

      res = await ts.call('PATCH', path, token: token, body: {'quantite': 2});
      expect(res.$2['quantite'], 2);
      expect(res.$2['quantite_initiale'], 8); // never decreases

      res = await ts.call('PATCH', path, token: token, body: {'quantite': -1});
      expect(res.$1, 400);
      res = await ts.call('PATCH', path,
          token: token, body: {'prix_centimes': 2000});
      expect(res.$1, 400); // initial price must stay above

      res = await ts.call('PATCH', path, token: token, body: {
        'titre': 'Panier gourmand',
        'prix_centimes': 700,
        'categorie': 'patisserie',
      });
      expect(res.$1, 200);
      expect(res.$2['titre'], 'Panier gourmand');
      expect(res.$2['prix_centimes'], 700);
      expect(res.$2['prix_initial_centimes'], 1500);
      expect(res.$2['categorie'], 'patisserie');
      expect(res.$2['quantite'], 2);
    });

    test('cancel makes the basket read-only', () async {
      final (token, _) = await ts.user('commercant');
      await ts.setupStore(token);
      final id = (await ts.createBasket(token))['id'];
      final path = '/foodsave/merchant/baskets/$id';

      var res = await ts.call('POST', '$path/cancel', token: token);
      expect(res.$1, 200);
      expect(res.$2['statut'], 'annule');

      res = await ts.call('PATCH', path, token: token, body: {'quantite': 4});
      expect(res.$1, 409);
      res = await ts.call('POST', '$path/cancel', token: token);
      expect(res.$1, 409);
      final img = await ts.raw('POST', '$path/image',
          token: token, bytes: pngBytes, contentType: 'image/png');
      expect(img.statusCode, 409);
    });

    test('DELETE only when the basket never had a reservation', () async {
      final (token, _) = await ts.user('commercant');
      final (_, clientId) = await ts.user('client');
      await ts.setupStore(token);
      final fresh = (await ts.createBasket(token))['id'];
      final used = (await ts.createBasket(token))['id'] as int;

      var res = await ts.call('DELETE', '/foodsave/merchant/baskets/$fresh',
          token: token);
      expect(res.$1, 204);
      res = await ts.call('GET', '/foodsave/merchant/baskets/$fresh',
          token: token);
      expect(res.$1, 404);

      await ts.insertReservation(
          basketId: used,
          clientId: clientId,
          statut: 'annule',
          statutPaiement: 'rembourse',
          date: CatalogTestServer.clock);
      res = await ts.call('DELETE', '/foodsave/merchant/baskets/$used',
          token: token);
      expect(res.$1, 409);
      expect(res.$2['error'], 'Annulez le panier : il a des réservations');
    });
  });

  group('images', () {
    test('upload checks type + magic bytes, serves, rejects traversal',
        () async {
      final (token, _) = await ts.user('commercant');
      final (clientToken, _) = await ts.user('client');
      await ts.setupStore(token);
      final id = (await ts.createBasket(token))['id'];
      final path = '/foodsave/merchant/baskets/$id/image';

      // Declared PNG but JPEG bytes / random bytes / unsupported type.
      for (final (bytes, type) in [
        (jpegBytes, 'image/png'),
        (Uint8List.fromList(utf8.encode('<svg></svg>')), 'image/png'),
        (pngBytes, 'image/gif'),
        (pngBytes, null),
      ]) {
        final r = await ts.raw('POST', path,
            token: token, bytes: bytes, contentType: type);
        expect(r.statusCode, 400, reason: '$type');
      }
      final tooBig = Uint8List(2 * 1024 * 1024 + 1)
        ..setRange(0, pngBytes.length, pngBytes);
      var r = await ts.raw('POST', path,
          token: token, bytes: tooBig, contentType: 'image/png');
      expect(r.statusCode, 413);

      r = await ts.raw('POST', path,
          token: token, bytes: pngBytes, contentType: 'image/png');
      expect(r.statusCode, 200);
      final first = (jsonDecode(await r.readAsString())
          as Map<String, dynamic>)['image'] as String;
      expect(first, matches(RegExp(r'^[a-f0-9]{32}\.png$')));
      expect(File(p.join(ts.uploads.path, first)).existsSync(), isTrue);

      // Any authenticated user can fetch it.
      r = await ts.raw('GET', '/foodsave/images/$first', token: clientToken);
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'image/png');
      expect(r.headers['cache-control'], contains('max-age=86400'));
      expect(await r.read().expand((c) => c).toList(), pngBytes);

      // Replacing deletes the old file.
      r = await ts.raw('POST', path,
          token: token, bytes: jpegBytes, contentType: 'image/jpeg');
      expect(r.statusCode, 200);
      final second = (jsonDecode(await r.readAsString())
          as Map<String, dynamic>)['image'] as String;
      expect(second, endsWith('.jpg'));
      expect(File(p.join(ts.uploads.path, first)).existsSync(), isFalse);
      r = await ts.raw('GET', '/foodsave/images/$second', token: clientToken);
      expect(r.headers['content-type'], 'image/jpeg');

      for (final bad in [
        '..%2F..%2Fpubspec.yaml',
        '..%5C..%5Cpubspec.yaml',
        'ABCDEF.png',
        '${'a' * 32}.gif',
      ]) {
        r = await ts.raw('GET', '/foodsave/images/$bad', token: clientToken);
        expect(r.statusCode, anyOf(400, 404), reason: bad);
      }
      r = await ts.raw('GET', '/foodsave/images/${'a' * 32}.png',
          token: clientToken);
      expect(r.statusCode, 404);

      // Deleting the basket removes its photo.
      await ts.call('DELETE', '/foodsave/merchant/baskets/$id', token: token);
      expect(File(p.join(ts.uploads.path, second)).existsSync(), isFalse);
    });
  });

  group('client catalogue', () {
    late String client;
    late int near;
    late int far;

    setUp(() async {
      final (m1, _) = await ts.user('commercant');
      final (m2, _) = await ts.user('commercant');
      final (c, clientId) = await ts.user('client');
      client = c;
      await ts.setupStore(m1, nom: 'Boulangerie Ameni');
      await ts.setupStore(m2,
          nom: 'Primeur La Marsa', lat: 36.8782, lng: 10.3247); // ~15 km
      await ts.setLocation(clientId, 36.8065, 10.1815); // ~0.6 km from m1

      near = (await ts.createBasket(m1, {
        'titre': 'Pains du jour',
        'prix_centimes': 500,
        'prix_initial_centimes': 1000, // -50 %
      }))['id'] as int;
      await ts.createBasket(m1, {
        'titre': 'Fruits de saison',
        'contenu': 'Pommes, poires_bio, oranges',
        'categorie': 'fruits_legumes',
        'prix_centimes': 300,
        'prix_initial_centimes': 1200, // -75 %
      });
      far = (await ts.createBasket(m2, {
        'titre': 'Légumes du marché',
        'contenu': 'Carottes, courgettes et tomates',
        'categorie': 'fruits_legumes',
        'prix_centimes': 800,
        'prix_initial_centimes': 1000, // -20 %
      }))['id'] as int;
      // Excluded: sold out, expired, pickup window closing within 5 min,
      // cancelled.
      final soldOut = (await ts.createBasket(m1, {'titre': 'Épuisé'}))['id'];
      await ts.call('PATCH', '/foodsave/merchant/baskets/$soldOut',
          token: m1, body: {'quantite': 0});
      final expired = (await ts.createBasket(m1, {'titre': 'Expiré'}))['id'];
      await ts.db.db.update('panier', {
        'date_expiration': iso(CatalogTestServer.clock),
      }, where: 'id = ?', whereArgs: [expired]);
      await ts.createBasket(m1, {
        'titre': 'Fin proche',
        'creneau_retrait_debut': iso(CatalogTestServer.clock),
        'creneau_retrait_fin':
            iso(CatalogTestServer.clock.add(const Duration(minutes: 4))),
      });
      final cancelled = (await ts.createBasket(m1, {'titre': 'Annulé'}))['id'];
      await ts.call('POST', '/foodsave/merchant/baskets/$cancelled/cancel',
          token: m1);
    });

    test('default: only reservable baskets, nearest first, with store',
        () async {
      final res = await ts.call('GET', '/foodsave/baskets', token: client);
      expect(res.$1, 200);
      final items = (res.$2['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((e) => e['titre']).toSet(),
          {'Pains du jour', 'Fruits de saison', 'Légumes du marché'});
      expect(items.last['titre'], 'Légumes du marché');
      expect(items.first['distance_km'], lessThan(1));
      expect(items.last['distance_km'], greaterThan(10));
      expect(items.first['commerce']['nom'], 'Boulangerie Ameni');
      expect(items.first['reservations_actives'], isNull);
    });

    test('category, search, radius and sort filters', () async {
      var res = await ts.call('GET', '/foodsave/baskets?categorie=fruits_legumes',
          token: client);
      expect(titles(res.$2), ['Fruits de saison', 'Légumes du marché']);

      res = await ts.call('GET', '/foodsave/baskets?q=PAINS', token: client);
      expect(titles(res.$2), ['Pains du jour']);
      res = await ts.call('GET', '/foodsave/baskets?q=primeur', token: client);
      expect(titles(res.$2), ['Légumes du marché']); // store name
      res = await ts.call('GET', '/foodsave/baskets?q=%25', token: client);
      expect(titles(res.$2), isEmpty); // '%' is literal, not a wildcard
      res = await ts.call('GET', '/foodsave/baskets?q=s_b', token: client);
      expect(titles(res.$2), ['Fruits de saison']); // '_' literal

      res = await ts.call('GET', '/foodsave/baskets?rayon_km=5', token: client);
      expect(titles(res.$2), isNot(contains('Légumes du marché')));
      expect(titles(res.$2), hasLength(2));

      res = await ts.call('GET', '/foodsave/baskets?tri=prix', token: client);
      expect(titles(res.$2),
          ['Fruits de saison', 'Pains du jour', 'Légumes du marché']);
      res =
          await ts.call('GET', '/foodsave/baskets?tri=reduction', token: client);
      expect(titles(res.$2),
          ['Fruits de saison', 'Pains du jour', 'Légumes du marché']);

      // Explicit position near the far store overrides the stored one.
      res = await ts.call('GET',
          '/foodsave/baskets?lat=36.8782&lng=10.3247&rayon_km=2',
          token: client);
      expect(titles(res.$2), ['Légumes du marché']);

      for (final bad in ['rayon_km=-1', 'rayon_km=abc', 'tri=nom',
          'categorie=viande']) {
        res = await ts.call('GET', '/foodsave/baskets?$bad', token: client);
        expect(res.$1, 400, reason: bad);
      }
    });

    test('without any position: distance null, radius ignored', () async {
      final (other, _) = await ts.user('client');
      final res = await ts.call('GET', '/foodsave/baskets?rayon_km=1',
          token: other);
      final items = (res.$2['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(3));
      expect(items.every((e) => e['distance_km'] == null), isTrue);
    });

    test('window closing soon disappears as the clock moves', () async {
      CatalogTestServer.clock =
          CatalogTestServer.clock.add(const Duration(hours: 2, minutes: 56));
      final res = await ts.call('GET', '/foodsave/baskets', token: client);
      expect(titles(res.$2), isEmpty);
    });

    test('basket detail shows any status with store + distance', () async {
      var res = await ts.call('GET', '/foodsave/baskets/$near', token: client);
      expect(res.$1, 200);
      expect(res.$2['commerce']['nom'], 'Boulangerie Ameni');
      expect(res.$2['distance_km'], lessThan(1));

      res = await ts.call('GET', '/foodsave/baskets/$far', token: client);
      expect(res.$2['distance_km'], greaterThan(10));

      final soldOut = await ts.db.db
          .query('panier', where: 'titre = ?', whereArgs: ['Épuisé']);
      res = await ts.call('GET', '/foodsave/baskets/${soldOut.first['id']}',
          token: client);
      expect(res.$1, 200);
      expect(res.$2['statut'], 'epuise');

      res = await ts.call('GET', '/foodsave/baskets/99999', token: client);
      expect(res.$1, 404);
    });
  });

  group('stats & jobs', () {
    test('stats shape: 7 UTC days, totals and rates', () async {
      final (token, _) = await ts.user('commercant');
      final (_, clientId) = await ts.user('client');
      await ts.setupStore(token);
      final id = (await ts.createBasket(token, {'quantite': 10}))['id'] as int;
      final now = CatalogTestServer.clock;

      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'retire',
          quantite: 2,
          montant: 1000,
          date: now.subtract(const Duration(days: 2)),
          retireLe: now.subtract(const Duration(days: 1)));
      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'retire',
          quantite: 1,
          montant: 500,
          date: now,
          retireLe: now);
      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'expire',
          montant: 500,
          date: now.subtract(const Duration(days: 1)));
      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'en_attente',
          montant: 500,
          date: now);
      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'annule',
          statutPaiement: 'rembourse',
          montant: 500,
          date: now);
      await ts.insertReservation(
          basketId: id,
          clientId: clientId,
          statut: 'retire',
          montant: 700,
          date: now.subtract(const Duration(days: 20)),
          retireLe: now.subtract(const Duration(days: 20)));

      final res =
          await ts.call('GET', '/foodsave/merchant/stats', token: token);
      expect(res.$1, 200);
      final body = res.$2;
      expect(body['paniers_actifs'], 1);
      expect(body['reservations_en_attente'], 1);
      expect(body['retraits_total'], 3);
      expect(body['repas_sauves'], 4);
      expect(body['revenus_centimes'], 1000 + 500 + 500 + 500 + 700);
      expect(body['taux_retrait'], 75); // 3 / (3 + 1)
      expect(body['par_statut'],
          {'en_attente': 1, 'retire': 3, 'expire': 1, 'annule': 1});

      final days = (body['par_jour'] as List).cast<Map<String, dynamic>>();
      expect(days, hasLength(7));
      expect(days.last['date'], '2030-03-10');
      expect(days.first['date'], '2030-03-04');
      expect(days.last['reservations'], 3);
      expect(days.last['retraits'], 1);
      expect(days.last['revenus_centimes'], 1000); // retire 500 + attente 500
      expect(days[5]['retraits'], 1);
      expect(days[5]['reservations'], 1);
      expect(days[4]['revenus_centimes'], 1000);
      expect(days[0]['reservations'], 0);
    });

    test('stats with no activity are zeros', () async {
      final (token, _) = await ts.user('commercant');
      final res =
          await ts.call('GET', '/foodsave/merchant/stats', token: token);
      expect(res.$1, 200);
      expect(res.$2['taux_retrait'], 0);
      expect(res.$2['revenus_centimes'], 0);
      expect(res.$2['par_jour'] as List, hasLength(7));
    });

    test('expireOutdatedBaskets uses the injected clock', () async {
      final (token, _) = await ts.user('commercant');
      await ts.setupStore(token);
      final a = (await ts.createBasket(token))['id'];
      final b = (await ts.createBasket(token, {
        'date_expiration':
            iso(CatalogTestServer.clock.add(const Duration(days: 1))),
      }))['id'];
      final soldOut = (await ts.createBasket(token))['id'];
      await ts.call('PATCH', '/foodsave/merchant/baskets/$soldOut',
          token: token, body: {'quantite': 0});

      final service = FoodSaveBasketService(ts.ctx);
      expect(await service.expireOutdatedBaskets(), 0);

      CatalogTestServer.clock =
          CatalogTestServer.clock.add(const Duration(hours: 5));
      expect(await service.expireOutdatedBaskets(), 2); // a + soldOut
      expect(await service.expireOutdatedBaskets(), 0);

      Future<String> statusOf(Object? id) async => (await ts.call(
              'GET', '/foodsave/merchant/baskets/$id',
              token: token))
          .$2['statut'] as String;
      expect(await statusOf(a), 'expire');
      expect(await statusOf(soldOut), 'expire');
      expect(await statusOf(b), 'disponible');

      final journal = await ts.db.db.query('foodsave_journal',
          where: 'evenement = ?', whereArgs: ['panier_expire']);
      expect(journal, hasLength(2));
    });
  });
}
