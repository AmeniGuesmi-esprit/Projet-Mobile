import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/qr_token_service.dart';
import 'package:proxilife_server/src/foodsave/services/reservation_service.dart';
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

class _User {
  const _User(this.id, this.token);
  final int id;
  final String token;
}

/// In-memory server with a controllable FoodSave clock.
class _Harness {
  _Harness._(this.database, this.handler, this.ctx, this.payments,
      this.sessions);

  final AppDatabase database;
  final Handler handler;
  final FoodSaveContext ctx;
  final PaymentService payments;
  final SessionService sessions;

  /// Fake "now" (UTC) used by every FoodSave service.
  static DateTime now = DateTime.utc(2026, 10, 13, 9);

  static Future<_Harness> create() async {
    now = DateTime.utc(2026, 10, 13, 9);
    final database = await AppDatabase.inMemory();
    final db = database.db;
    // Workaround: a fresh database (onCreate) may not run the v2 FoodSave
    // migration; create the tables when they are missing.
    final hasFoodSave = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'panier'");
    if (hasFoodSave.isEmpty) await createFoodSaveSchema(db);
    final users = UserRepository(db);
    final payments = PaymentService(
      db: db,
      users: users,
      methods: PaymentMethodRepository(db),
      transactions: TransactionRepository(db),
    );
    final ctx = FoodSaveContext(
      db: db,
      users: users,
      payments: payments,
      uploadsDir: 'build/test_uploads',
      clock: () => now,
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
    return _Harness._(
        database, handler, ctx, payments, SessionService(db, users));
  }

  FoodSaveReservationService get service => FoodSaveReservationService(ctx);

  Future<void> close() => database.close();

  Future<_User> user(String email,
      {String role = 'client',
      String prenom = 'Ameni',
      String nom = 'Guesmi',
      int solde = 0}) async {
    final id = await database.db.insert('utilisateur', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': '0612345678',
      'mot_de_passe_hash': 'x',
      'role': role,
      'statut_compte': 'actif',
      'rib': role == 'client' ? null : '30004000011234567890173',
      'solde_centimes': solde,
      'cree_le': now.toIso8601String(),
    });
    return _User(id, await sessions.createSession(id));
  }

  Future<_User> merchant(String email, {double lat = 36.8}) async {
    final m = await user(email, role: 'commercant', prenom: 'Sami');
    await database.db.insert('commerce', {
      'commercant_id': m.id,
      'nom': 'Boulangerie $email',
      'adresse': '1 rue de Tunis',
      'latitude': lat,
      'longitude': 10.18,
      'categorie': 'boulangerie',
      'cree_le': now.toIso8601String(),
      'mis_a_jour_le': now.toIso8601String(),
    });
    return m;
  }

  /// Pickup window [now+start, now+end], basket expires at now+end+1h.
  Future<int> basket(int merchantId,
      {int quantite = 3,
      int prix = 500,
      Duration start = const Duration(hours: 1),
      Duration end = const Duration(hours: 3)}) {
    return database.db.insert('panier', {
      'titre': 'Panier du soir',
      'contenu': 'Pains et viennoiseries',
      'categorie': 'boulangerie',
      'prix_centimes': prix,
      'prix_initial_centimes': prix * 3,
      'quantite': quantite,
      'quantite_initiale': quantite,
      'creneau_retrait_debut': now.add(start).toIso8601String(),
      'creneau_retrait_fin': now.add(end).toIso8601String(),
      'date_expiration':
          now.add(end + const Duration(hours: 1)).toIso8601String(),
      'statut': 'disponible',
      'commercant_id': merchantId,
      'cree_le': now.toIso8601String(),
      'mis_a_jour_le': now.toIso8601String(),
    });
  }

  Future<int> method(int userId,
      {PaymentMethodType type = PaymentMethodType.especes}) async {
    final dto = await payments.addMethod(userId, type: type);
    return dto.id;
  }

  Future<Map<String, Object?>> basketRow(int id) async =>
      (await database.db.query('panier', where: 'id = ?', whereArgs: [id]))
          .first;

  Future<Map<String, Object?>> reservationRow(int id) async => (await database
          .db
          .query('reservation', where: 'id = ?', whereArgs: [id]))
      .first;

  Future<int> soldeOf(int userId) async => (await database.db.query(
          'utilisateur',
          where: 'id = ?',
          whereArgs: [userId]))
      .first['solde_centimes'] as int;

  Future<int> count(String table, [String? where, List<Object?>? args]) async =>
      (await database.db.query(table, where: where, whereArgs: args)).length;

  Future<(int, Map<String, dynamic>)> call(String verb, String path,
      {Map<String, dynamic>? body, required String token}) async {
    final response = await handler(Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
    ));
    final raw = await response.readAsString();
    return (
      response.statusCode,
      raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<(int, Map<String, dynamic>)> reserve(_User client, int basketId,
          {int quantite = 1, int? methodId}) =>
      call('POST', '/foodsave/reservations',
          token: client.token,
          body: {
            'panier_id': basketId,
            'quantite': quantite,
            'moyen_paiement_id': methodId,
          });

  Future<(int, Map<String, dynamic>)> scan(_User merchant, String token) =>
      call('POST', '/foodsave/merchant/scan',
          token: merchant.token, body: {'token': token});
}

void main() {
  late _Harness h;
  late _User merchant;
  late _User client;
  late int basketId;
  late int methodId;

  setUp(() async {
    h = await _Harness.create();
    merchant = await h.merchant('commerce@test.fr');
    client = await h.user('client@test.fr');
    basketId = await h.basket(merchant.id);
    methodId = await h.method(client.id);
  });

  tearDown(() async => h.close());

  group('reserve', () {
    test('nominal: QR token, units taken, FoodSave transaction', () async {
      final (status, body) =
          await h.reserve(client, basketId, quantite: 2, methodId: methodId);
      expect(status, 201, reason: '$body');
      final dto = ReservationDto.fromJson(body);
      expect(dto.statut, ReservationStatus.enAttente);
      expect(dto.statutPaiement, TransactionStatus.paye);
      expect(dto.montantCentimes, 1000);
      expect(dto.modePaiement, PaymentMethodType.especes);
      expect(dto.qrToken, matches(RegExp(r'^FS1\.\d+\.[\w-]{22}\.[\w-]{43}$')));
      expect(dto.qrToken!.split('.')[1], '${dto.id}');
      expect(dto.panier?.commerce?.nom, 'Boulangerie commerce@test.fr');
      expect(dto.factureNumero, isNotNull);
      // Reserved before the window opens → valid until the window end.
      expect(dto.dateExpirationQr, _Harness.now.add(const Duration(hours: 3)));

      final basket = await h.basketRow(basketId);
      expect(basket['quantite'], 1);
      expect(basket['statut'], 'disponible');

      final tx = (await h.database.db.query('transaction_',
              where: 'id = ?', whereArgs: [dto.transactionId]))
          .first;
      expect(tx['type_service'], 'FoodSave');
      expect(tx['statut'], 'paye');
      expect(tx['id_reference'], 'FS-RES-${dto.id}');
      expect(tx['montant_centimes'], 1000);
      expect(tx['beneficiaire_id'], merchant.id);
      expect(await h.soldeOf(merchant.id), 1000);

      expect(
          await h.count('foodsave_notification', 'type = ? AND utilisateur_id = ?',
              ['reservation_confirmee', client.id]),
          1);
      expect(await h.count('foodsave_journal', 'evenement = ?', ['qr_genere']),
          1);

      // The client's list exposes the QR, the merchant view never does.
      final (_, list) =
          await h.call('GET', '/foodsave/reservations', token: client.token);
      expect((list['items'] as List).single['qr_token'], dto.qrToken);
      final (mStatus, mBody) = await h.call(
          'GET', '/foodsave/reservations/${dto.id}',
          token: merchant.token);
      expect(mStatus, 200);
      expect(mBody['qr_token'], isNull);
      expect(mBody['client_nom'], 'Ameni G.');
      final (_, mList) = await h.call('GET',
          '/foodsave/merchant/reservations?panier_id=$basketId&statut=en_attente',
          token: merchant.token);
      expect((mList['items'] as List).single['qr_token'], isNull);
      expect((mList['items'] as List).single['client_nom'], 'Ameni G.');

      // Strangers get a 404, clients can't use the merchant list.
      final stranger = await h.user('autre@test.fr');
      final (sStatus, _) = await h.call(
          'GET', '/foodsave/reservations/${dto.id}',
          token: stranger.token);
      expect(sStatus, 404);
      final (cStatus, _) = await h.call('GET', '/foodsave/merchant/reservations',
          token: client.token);
      expect(cStatus, 403);
    });

    test('quantity above stock → 409 and nothing changes', () async {
      final (status, body) =
          await h.reserve(client, basketId, quantite: 4, methodId: methodId);
      expect(status, 409);
      expect(body['error'], contains('Quantité insuffisante'));
      expect((await h.basketRow(basketId))['quantite'], 3);
      expect(await h.count('reservation'), 0);
      expect(await h.count('transaction_'), 0);
    });

    test('invalid quantity / unknown basket / other people\'s method', () async {
      expect((await h.reserve(client, basketId, quantite: 0)).$1, 400);
      expect((await h.reserve(client, basketId, quantite: 21)).$1, 400);
      expect((await h.reserve(client, 9999, methodId: methodId)).$1, 404);
      final other = await h.user('other@test.fr');
      final otherMethod = await h.method(other.id);
      expect(
          (await h.reserve(client, basketId, methodId: otherMethod)).$1, 404);
      expect((await h.basketRow(basketId))['quantite'], 3);
    });

    test('last unit → basket epuise, then 409 épuisé', () async {
      final (status, _) =
          await h.reserve(client, basketId, quantite: 3, methodId: methodId);
      expect(status, 201);
      final basket = await h.basketRow(basketId);
      expect(basket['quantite'], 0);
      expect(basket['statut'], 'epuise');
      final (again, body) = await h.reserve(client, basketId, methodId: methodId);
      expect(again, 409);
      expect(body['error'], contains('épuisé'));
    });

    test('pickup window too close → 409', () async {
      final closing = await h.basket(merchant.id,
          start: const Duration(minutes: -30),
          end: const Duration(minutes: 4));
      final (status, body) = await h.reserve(client, closing, methodId: methodId);
      expect(status, 409);
      expect(body['error'], contains('créneau'));
    });

    test('insufficient wallet → 402, annule, units restored exactly once',
        () async {
      final wallet =
          await h.method(client.id, type: PaymentMethodType.portefeuille);
      final (status, body) =
          await h.reserve(client, basketId, quantite: 3, methodId: wallet);
      expect(status, 402);
      expect(body['error'], contains('solde insuffisant'));

      final res = (await h.database.db.query('reservation')).single;
      expect(res['statut'], 'annule');
      expect(res['statut_paiement'], 'echoue');
      expect(res['quantite_liberee'], 3);
      expect(res['qr_nonce'], isNull);
      var basket = await h.basketRow(basketId);
      expect(basket['quantite'], 3);
      expect(basket['statut'], 'disponible');

      // Nothing can release it a second time.
      await h.service.expireDue();
      _Harness.now = _Harness.now.add(const Duration(days: 1));
      await h.service.expireDue();
      basket = await h.basketRow(basketId);
      expect(basket['quantite'], 3);
      expect(
          await h.count('foodsave_journal', 'evenement = ?', ['quantite_liberee']),
          1);
      expect(await h.soldeOf(merchant.id), 0);
    });

    test('a merchant cannot reserve its own basket', () async {
      final own = await h.method(merchant.id);
      final (status, _) = await h.reserve(merchant, basketId, methodId: own);
      expect(status, 403);
      expect((await h.basketRow(basketId))['quantite'], 3);
    });

    test('concurrent reservations never oversell', () async {
      final clients = <_User>[];
      final methods = <int>[];
      for (var i = 0; i < 5; i++) {
        final c = await h.user('c$i@test.fr');
        clients.add(c);
        methods.add(await h.method(c.id));
      }
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          h.reserve(clients[i], basketId, methodId: methods[i]),
      ]);
      final statuses = results.map((r) => r.$1).toList();
      expect(statuses.where((s) => s == 201).length, 3, reason: '$statuses');
      expect(statuses.where((s) => s == 409).length, 2, reason: '$statuses');
      final basket = await h.basketRow(basketId);
      expect(basket['quantite'], 0);
      expect(basket['statut'], 'epuise');
      expect(await h.count('reservation'), 3);
      expect(await h.soldeOf(merchant.id), 1500);
    });
  });

  group('scan', () {
    late ReservationDto reservation;

    setUp(() async {
      final (status, body) =
          await h.reserve(client, basketId, quantite: 2, methodId: methodId);
      expect(status, 201);
      reservation = ReservationDto.fromJson(body);
    });

    test('accepted once, then deja_utilise', () async {
      final (status, body) = await h.scan(merchant, reservation.qrToken!);
      expect(status, 200);
      final result = ScanResultDto.fromJson(body);
      expect(result.resultat, ScanOutcome.accepte);
      expect(result.message,
          'Retrait validé : remettez 2 × Panier du soir à Ameni G.');
      expect(result.reservation?.qrToken, isNull);
      expect(result.reservation?.statut, ReservationStatus.retire);

      final row = await h.reservationRow(reservation.id);
      expect(row['statut'], 'retire');
      expect(row['retire_le'], _Harness.now.toIso8601String());
      expect(row['qr_nonce'], isNull);
      expect(
          await h.count('foodsave_notification', 'type = ?', ['retrait_effectue']),
          1);

      final again = ScanResultDto.fromJson(
          (await h.scan(merchant, reservation.qrToken!)).$2);
      expect(again.resultat, ScanOutcome.dejaUtilise);

      // The retired reservation no longer exposes its QR to the client.
      final (_, mine) = await h.call(
          'GET', '/foodsave/reservations/${reservation.id}',
          token: client.token);
      expect(mine['qr_token'], isNull);
      expect(mine['statut'], 'retire');
      // Units stay taken.
      expect((await h.basketRow(basketId))['quantite'], 1);
    });

    test('forged / unknown / old nonce / garbage → invalide', () async {
      final token = reservation.qrToken!;
      final parts = token.split('.');
      final forgedSig = parts[3].startsWith('A')
          ? 'B${parts[3].substring(1)}'
          : 'A${parts[3].substring(1)}';
      final qr = FoodSaveQrTokenService(h.ctx);
      final candidates = [
        '${parts[0]}.${parts[1]}.${parts[2]}.$forgedSig',
        await qr.sign(9999, FoodSaveQrTokenService.newNonce()),
        await qr.sign(reservation.id, FoodSaveQrTokenService.newNonce()),
        'pas-un-qr',
        '${parts[0]}.${parts[1]}.${parts[2]}',
      ];
      for (final candidate in candidates) {
        final (status, body) = await h.scan(merchant, candidate);
        expect(status, 200);
        expect(body['resultat'], 'invalide', reason: candidate);
      }
      expect((await h.reservationRow(reservation.id))['statut'], 'en_attente');

      // Malformed body is a 400.
      final (status, _) = await h.call('POST', '/foodsave/merchant/scan',
          token: merchant.token, body: {'token': 42});
      expect(status, 400);
      // Clients can't scan.
      final (forbidden, _) = await h.scan(client, token);
      expect(forbidden, 403);
    });

    test('another merchant → autre_commercant', () async {
      final other = await h.merchant('autre@test.fr', lat: 36.9);
      final result = ScanResultDto.fromJson(
          (await h.scan(other, reservation.qrToken!)).$2);
      expect(result.resultat, ScanOutcome.autreCommercant);
      expect(result.reservation, isNull);
      expect((await h.reservationRow(reservation.id))['statut'], 'en_attente');
    });

    test('expired QR at scan time → expire + units restored', () async {
      _Harness.now = _Harness.now.add(const Duration(hours: 3, minutes: 1));
      final result = ScanResultDto.fromJson(
          (await h.scan(merchant, reservation.qrToken!)).$2);
      expect(result.resultat, ScanOutcome.expire);
      final row = await h.reservationRow(reservation.id);
      expect(row['statut'], 'expire');
      expect(row['statut_paiement'], 'paye'); // no automatic refund
      expect((await h.basketRow(basketId))['quantite'], 3);
      expect(
          await h.count(
              'foodsave_notification', 'type = ?', ['reservation_expiree']),
          1);
    });

    test('expireDue twice releases once; scan afterwards → expire', () async {
      _Harness.now = _Harness.now.add(const Duration(hours: 4));
      expect(await h.service.expireDue(), 1);
      expect(await h.service.expireDue(), 0);
      expect((await h.basketRow(basketId))['quantite'], 3);
      expect(
          await h.count('foodsave_journal', 'evenement = ?', ['quantite_liberee']),
          1);
      final result = ScanResultDto.fromJson(
          (await h.scan(merchant, reservation.qrToken!)).$2);
      expect(result.resultat, ScanOutcome.expire);
      expect((await h.basketRow(basketId))['quantite'], 3);
    });

    test('an expired sold-out basket comes back on sale', () async {
      final (status, _) =
          await h.reserve(client, basketId, quantite: 1, methodId: methodId);
      expect(status, 201);
      expect((await h.basketRow(basketId))['statut'], 'epuise');
      _Harness.now = _Harness.now.add(const Duration(hours: 3, minutes: 1));
      expect(await h.service.expireDue(), 2);
      final basket = await h.basketRow(basketId);
      expect(basket['quantite'], 3);
      expect(basket['statut'], 'disponible');
    });
  });

  group('cancel', () {
    test('cancel a sold-out basket → back on sale with its units', () async {
      final soldOut = await h.basket(merchant.id, quantite: 2);
      final (_, body) =
          await h.reserve(client, soldOut, quantite: 2, methodId: methodId);
      final dto = ReservationDto.fromJson(body);
      expect((await h.basketRow(soldOut))['quantite'], 0);
      expect((await h.basketRow(soldOut))['statut'], 'epuise');

      final (status, _) = await h.call(
          'POST', '/foodsave/reservations/${dto.id}/cancel',
          token: client.token);
      expect(status, 200);
      final basket = await h.basketRow(soldOut);
      expect(basket['quantite'], 2);
      expect(basket['statut'], 'disponible');
    });

    test('units released after the basket expired → not back on sale',
        () async {
      final (status, _) =
          await h.reserve(client, basketId, quantite: 3, methodId: methodId);
      expect(status, 201);
      expect((await h.basketRow(basketId))['statut'], 'epuise');
      // Past the basket's own expiry (window end + 1 h).
      _Harness.now = _Harness.now.add(const Duration(hours: 4, minutes: 1));
      expect(await h.service.expireDue(), 1);
      final basket = await h.basketRow(basketId);
      expect(basket['quantite'], 3);
      expect(basket['statut'], 'epuise');
    });

    test('client cancel → units restored + refund', () async {
      final (_, body) =
          await h.reserve(client, basketId, quantite: 2, methodId: methodId);
      final dto = ReservationDto.fromJson(body);
      expect(await h.soldeOf(merchant.id), 1000);

      final (status, cancelled) = await h.call(
          'POST', '/foodsave/reservations/${dto.id}/cancel',
          token: client.token);
      expect(status, 200, reason: '$cancelled');
      expect(cancelled['statut'], 'annule');
      expect(cancelled['statut_paiement'], 'rembourse');
      expect(cancelled['qr_token'], isNull);
      expect((await h.basketRow(basketId))['quantite'], 3);
      expect(await h.soldeOf(merchant.id), 0);
      final tx = (await h.database.db.query('transaction_',
              where: 'id = ?', whereArgs: [dto.transactionId]))
          .first;
      expect(tx['statut'], 'rembourse');

      // Cancelled QR can't be used, nor cancelled twice.
      final scan = ScanResultDto.fromJson(
          (await h.scan(merchant, dto.qrToken!)).$2);
      expect(scan.resultat, ScanOutcome.annule);
      final (again, _) = await h.call(
          'POST', '/foodsave/reservations/${dto.id}/cancel',
          token: client.token);
      expect(again, 409);
      expect((await h.basketRow(basketId))['quantite'], 3);

      // Someone else's reservation is invisible.
      final stranger = await h.user('stranger@test.fr');
      final (other, _) = await h.call(
          'POST', '/foodsave/reservations/${dto.id}/cancel',
          token: stranger.token);
      expect(other, 404);
    });

    test('refund impossible → stays paye, journal remboursement_a_traiter',
        () async {
      final (_, body) =
          await h.reserve(client, basketId, quantite: 1, methodId: methodId);
      final dto = ReservationDto.fromJson(body);
      // The merchant already cashed out its balance.
      await h.database.db.update('utilisateur', {'solde_centimes': 0},
          where: 'id = ?', whereArgs: [merchant.id]);
      final (status, cancelled) = await h.call(
          'POST', '/foodsave/reservations/${dto.id}/cancel',
          token: client.token);
      expect(status, 200);
      expect(cancelled['statut'], 'annule');
      expect(cancelled['statut_paiement'], 'paye');
      expect(
          await h.count(
              'foodsave_journal', 'evenement = ?', ['remboursement_a_traiter']),
          1);
      expect((await h.basketRow(basketId))['quantite'], 3);
    });

    test('cancelActiveForBasket cancels, refunds and notifies', () async {
      final other = await h.user('second@test.fr', prenom: 'Lina');
      final otherMethod = await h.method(other.id);
      await h.reserve(client, basketId, quantite: 1, methodId: methodId);
      final (_, second) =
          await h.reserve(other, basketId, quantite: 2, methodId: otherMethod);
      // Simulate the catalog: the basket is cancelled first.
      await h.database.db.update('panier', {'statut': 'annule'},
          where: 'id = ?', whereArgs: [basketId]);

      final strangerMerchant = await h.merchant('x@test.fr', lat: 37);
      expect(
          await h.service
              .cancelActiveForBasket(basketId, merchantId: strangerMerchant.id),
          0);
      expect(
          await h.service
              .cancelActiveForBasket(basketId, merchantId: merchant.id),
          2);
      expect(
          await h.service
              .cancelActiveForBasket(basketId, merchantId: merchant.id),
          0);

      final rows = await h.database.db.query('reservation');
      expect(rows.every((r) => r['statut'] == 'annule'), isTrue);
      expect(rows.every((r) => r['statut_paiement'] == 'rembourse'), isTrue);
      expect(await h.soldeOf(merchant.id), 0);
      final basket = await h.basketRow(basketId);
      expect(basket['statut'], 'annule'); // terminal status kept
      expect(basket['quantite'], 3);
      expect(
          await h.count('foodsave_notification', 'type = ?', ['panier_annule']),
          2);
      final scan = ScanResultDto.fromJson(
          (await h.scan(merchant, second['qr_token'] as String)).$2);
      expect(scan.resultat, ScanOutcome.annule);
    });
  });

  group('jobs', () {
    test('warnExpiringSoon notifies once per reservation', () async {
      // The window is already open → QR valid for qrTtl (30 min).
      final open = await h.basket(merchant.id,
          start: const Duration(minutes: -10), end: const Duration(hours: 2));
      final (status, body) = await h.reserve(client, open, methodId: methodId);
      expect(status, 201);
      expect(ReservationDto.fromJson(body).dateExpirationQr,
          _Harness.now.add(const Duration(minutes: 30)));

      expect(await h.service.warnExpiringSoon(), 0);
      _Harness.now = _Harness.now.add(const Duration(minutes: 25));
      expect(await h.service.warnExpiringSoon(), 1);
      expect(await h.service.warnExpiringSoon(), 0);
      expect(
          await h.count(
              'foodsave_notification', 'type = ?', ['qr_expire_bientot']),
          1);

      // Reading it after expiry lazily expires it (no QR any more).
      _Harness.now = _Harness.now.add(const Duration(minutes: 10));
      final (_, list) =
          await h.call('GET', '/foodsave/reservations', token: client.token);
      final item = (list['items'] as List).single as Map<String, dynamic>;
      expect(item['statut'], 'expire');
      expect(item['qr_token'], isNull);
      expect((await h.basketRow(open))['quantite'], 3);
    });

    test('stale unpaid reservation is cancelled and released', () async {
      final nowIso = _Harness.now.toIso8601String();
      await h.database.db.rawUpdate(
          'UPDATE panier SET quantite = quantite - 1 WHERE id = ?', [basketId]);
      final id = await h.database.db.insert('reservation', {
        'date': nowIso,
        'statut': 'en_attente',
        'panier_id': basketId,
        'client_id': client.id,
        'quantite_reservee': 1,
        'montant_centimes': 500,
        'statut_paiement': 'en_attente',
        'cree_le': nowIso,
      });
      await h.service.expireDue();
      expect((await h.reservationRow(id))['statut'], 'en_attente');
      _Harness.now = _Harness.now.add(const Duration(minutes: 11));
      await h.service.expireDue();
      final row = await h.reservationRow(id);
      expect(row['statut'], 'annule');
      expect(row['statut_paiement'], 'echoue');
      expect((await h.basketRow(basketId))['quantite'], 3);
    });
  });

  test('QR secret is created once and reused', () async {
    final a = FoodSaveQrTokenService(h.ctx);
    final token = await a.sign(1, FoodSaveQrTokenService.newNonce());
    expect(await FoodSaveQrTokenService(h.ctx).verify(token), isNotNull);
    expect(await h.count('foodsave_parametre', 'cle = ?', ['qr_secret']), 1);
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
    expect(constantTimeEquals('abc', 'abcd'), isFalse);
  });
}
