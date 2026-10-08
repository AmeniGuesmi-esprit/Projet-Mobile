import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class FakeEmailSender implements EmailSender {
  final Map<String, String> lastCodeByEmail = {};

  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
    lastCodeByEmail[to] = code;
  }
}

class TestServer {
  TestServer(this.handler, this.emails, this._db);

  final Handler handler;
  final FakeEmailSender emails;
  final AppDatabase _db;

  Future<void> close() => _db.close();

  Future<int> soldeOf(int userId) async {
    final rows = await _db.db
        .query('utilisateur', where: 'id = ?', whereArgs: [userId]);
    return rows.first['solde_centimes'] as int;
  }

  static Future<TestServer> create() async {
    final db = await AppDatabase.inMemory();
    final emails = FakeEmailSender();
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
      emailSender: emails,
      logRequestsMiddleware: false,
    );
    return TestServer(handler, emails, db);
  }

  Future<(int, Map<String, dynamic>)> call(
    String verb,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    );
    final response = await handler(request);
    final raw = await response.readAsString();
    return (
      response.statusCode,
      raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<(String token, int userId)> registerLogin({
    required String email,
    String role = 'client',
    String? rib,
    int solde = 0,
  }) async {
    await call('POST', '/auth/register', body: {
      'nom': 'Doe',
      'prenom': 'John',
      'email': email,
      'telephone': '0612345678',
      'mot_de_passe': 'Proxilife2026!',
      'role': role,
      if (rib != null) 'rib': rib,
    });
    final code = emails.lastCodeByEmail[email]!;
    await call('POST', '/auth/verify', body: {'email': email, 'code': code});
    final (status, body) = await call('POST', '/auth/login',
        body: {'email': email, 'mot_de_passe': 'Proxilife2026!'});
    if (status != 200) fail('login failed: ${body['error']}');
    final userId = body['utilisateur']['id'] as int;
    if (solde > 0) {
      await _db.db.update('utilisateur', {'solde_centimes': solde},
          where: 'id = ?', whereArgs: [userId]);
    }
    return (body['token'] as String, userId);
  }
}

const validRib = '30004000011234567890173';
const validCard = '4539 1488 0343 6467';

void main() {
  late TestServer ts;

  setUp(() async {
    ts = await TestServer.create();
  });

  tearDown(() async {
    await ts.close();
  });

  group('payment methods', () {
    test('add card validates Luhn and expiry; first method becomes default',
        () async {
      final (token, _) = await ts.registerLogin(email: 'pay@test.fr');

      var result = await ts.call('POST', '/payment-methods', token: token, body: {
        'type': 'carte_bancaire',
        'numero_carte': '1111 1111 1111 1111',
        'nom_titulaire': 'JOHN DOE',
        'date_expiration': '10/29',
      });
      expect(result.$1, 400); // Luhn failure

      result = await ts.call('POST', '/payment-methods', token: token, body: {
        'type': 'carte_bancaire',
        'numero_carte': validCard,
        'nom_titulaire': 'JOHN DOE',
        'date_expiration': '10/29',
      });
      expect(result.$1, 201);
      expect(result.$2['quatre_derniers_chiffres'], '6467');
      expect(result.$2['par_defaut'], isTrue);
      expect(result.$2['type'], 'carte_bancaire');
    });

    test('full CRUD + default switching', () async {
      final (token, _) = await ts.registerLogin(email: 'pay2@test.fr');

      Future<int> add(Map<String, dynamic> body) async {
        final (status, json) =
            await ts.call('POST', '/payment-methods', token: token, body: body);
        expect(status, 201);
        return json['id'] as int;
      }

      final cardId = await add({
        'type': 'carte_bancaire',
        'numero_carte': validCard,
        'nom_titulaire': 'JOHN DOE',
        'date_expiration': '10/29',
      });
      final walletId = await add({'type': 'portefeuille'});
      final cashId = await add({'type': 'especes'});

      var (status, json) =
          await ts.call('GET', '/payment-methods', token: token);
      expect(status, 200);
      expect((json['items'] as List).length, 3);

      // Switch default from card to wallet.
      (status, _) = await ts.call(
          'PATCH', '/payment-methods/$walletId/default',
          token: token);
      expect(status, 200);

      (status, json) = await ts.call('GET', '/payment-methods', token: token);
      final defaults = (json['items'] as List)
          .where((m) => m['par_defaut'] == true)
          .toList();
      expect(defaults, hasLength(1));
      expect(defaults.first['id'], walletId);

      // Update expiry of the card.
      (status, json) = await ts.call('PATCH', '/payment-methods/$cardId',
          token: token, body: {'date_expiration': '12/30'});
      expect(status, 200);
      expect(json['date_expiration'], '12/30');

      // Delete wallet (the default) -> default reassigned to another method.
      (status, _) = await ts.call(
          'DELETE', '/payment-methods/$walletId', token: token);
      expect(status, 204);
      (status, json) = await ts.call('GET', '/payment-methods', token: token);
      final remaining = json['items'] as List;
      expect(remaining, hasLength(2));
      expect(remaining.where((m) => m['par_defaut'] == true), hasLength(1));

      // Cannot delete someone else's method.
      final (token2, _) = await ts.registerLogin(email: 'other@test.fr');
      (status, _) = await ts.call(
          'DELETE', '/payment-methods/$cashId', token: token2);
      expect(status, 404);
    });
  });

  group('transactions', () {
    Future<(String payerToken, int payerId, int proId)> base() async {
      final p = await ts.registerLogin(email: 'payer@test.fr', solde: 5000);
      final pro = await ts.registerLogin(
          email: 'pro@test.fr', role: 'conducteur', rib: validRib);
      return (p.$1, p.$2, pro.$2);
    }

    test('wallet payment settles both balances; credit card is simulated',
        () async {
      final (token, payerId, proId) = await base();

      await ts.call('POST', '/payment-methods',
          token: token, body: {'type': 'portefeuille'});

      final (status, json) = await ts.call('POST', '/transactions',
          token: token,
          body: {
            'montant_centimes': 2599,
            'beneficiaire_email': 'pro@test.fr',
            'type_service': 'EcoRoute',
            'id_reference': 'TRIP-1',
          });
      expect(status, 201);
      expect(json['statut'], 'paye');
      expect(json['facture_numero'], matches(r'^FAC-\d{4}-\d{6}$'));

      expect(await ts.soldeOf(payerId), 5000 - 2599);
      expect(await ts.soldeOf(proId), 2599);
    });

    test('insufficient wallet yields an echoue transaction', () async {
      final (token, payerId, proId) = await base();
      await ts.call('POST', '/payment-methods',
          token: token, body: {'type': 'portefeuille'});

      final (status, json) = await ts.call('POST', '/transactions',
          token: token,
          body: {
            'montant_centimes': 99999,
            'beneficiaire_email': 'pro@test.fr',
            'type_service': 'EcoRoute',
          });
      expect(status, 201);
      expect(json['statut'], 'echoue');

      // Balances unchanged.
      expect(await ts.soldeOf(payerId), 5000);
      expect(await ts.soldeOf(proId), 0);
    });

    test('rejects invalid beneficiaries and self-payment', () async {
      final payerPair = await base();
      final token = payerPair.$1;

      var (status, body) = await ts.call('POST', '/transactions',
          token: token,
          body: {
            'montant_centimes': 100,
            'beneficiaire_email': 'nobody@test.fr',
            'type_service': 'EcoRoute',
          });
      expect(status, 404);

      // Payer also registered as client (cannot receive).
      (status, body) = await ts.call('POST', '/transactions',
          token: token,
          body: {
            'montant_centimes': 100,
            'beneficiaire_email': 'payer@test.fr',
            'type_service': 'EcoRoute',
          });
      expect(status, 400);

      // Professional without RIB.
      await ts.registerLogin(email: 'norib@test.fr', role: 'coach', rib: validRib);
      final noRibId = 3; // created after payer & pro
      await ts._db.db.update('utilisateur', {'rib': null},
          where: 'id = ?', whereArgs: [noRibId]);
      (status, body) = await ts.call('POST', '/transactions',
          token: token,
          body: {
            'montant_centimes': 100,
            'beneficiaire_email': 'norib@test.fr',
            'type_service': 'CoachProche',
          });
      expect(status, 400);
      expect(body['error'], contains('RIB'));
    });

    test('refund reverses balances; non-payer cannot refund', () async {
      final p = await ts.registerLogin(email: 'payer@test.fr', solde: 5000);
      final pro = await ts.registerLogin(
          email: 'pro@test.fr', role: 'conducteur', rib: validRib);
      await ts.call('POST', '/payment-methods',
          token: p.$1, body: {'type': 'portefeuille'});
      final (status, json) = await ts.call('POST', '/transactions',
          token: p.$1,
          body: {
            'montant_centimes': 2599,
            'beneficiaire_email': 'pro@test.fr',
            'type_service': 'FoodSave',
          });
      expect(status, 201);
      final transactionId = json['id'] as int;

      // The beneficiary cannot refund.
      var result = await ts.call('PATCH', '/transactions/$transactionId/status',
          token: pro.$1, body: {'statut': 'rembourse'});
      expect(result.$1, 403);

      result = await ts.call('PATCH', '/transactions/$transactionId/status',
          token: p.$1, body: {'statut': 'rembourse'});
      expect(result.$1, 200);
      expect(result.$2['statut'], 'rembourse');

      expect(await ts.soldeOf(p.$2), 5000);
      expect(await ts.soldeOf(pro.$2), 0);

      // Second refund refused.
      result = await ts.call('PATCH', '/transactions/$transactionId/status',
          token: p.$1, body: {'statut': 'rembourse'});
      expect(result.$1, 409);
    });

    test('invoice detail respects privacy rules', () async {
      final p = await ts.registerLogin(email: 'payer@test.fr', solde: 5000);
      await ts.registerLogin(
          email: 'pro@test.fr', role: 'conducteur', rib: validRib);
      final third =
          await ts.registerLogin(email: 'third@test.fr');
      await ts.call('POST', '/payment-methods',
          token: p.$1, body: {'type': 'especes'});
      final (_, json) = await ts.call('POST', '/transactions',
          token: p.$1,
          body: {
            'montant_centimes': 500,
            'beneficiaire_email': 'pro@test.fr',
            'type_service': 'TeleDoc',
          });
      final transactionId = json['id'] as int;

      // Third user cannot see the invoice.
      final (forbid, _) = await ts.call(
          'GET', '/transactions/$transactionId',
          token: third.$1);
      expect(forbid, 403);

      final (status, detail) = await ts.call('GET', '/transactions/$transactionId',
          token: p.$1);
      expect(status, 200);
      expect(detail['beneficiaire_nom'], 'John Doe');
      expect(detail['facture_numero'], isNotEmpty);

      // List filters by statut/type_service.
      var (listStatus, listJson) = await ts.call(
          'GET', '/transactions?statut=paye&type_service=TeleDoc',
          token: p.$1);
      expect(listStatus, 200);
      expect((listJson['items'] as List), hasLength(1));

      listStatus = (await ts.call('GET', '/transactions?statut=echec',
              token: p.$1))
          .$1;
      expect(listStatus, 400); // unknown enum value
    });

    test('delete account refused with pending transactions', () async {
      // A pending transaction is only possible via direct insert here.
      final p = await ts.registerLogin(email: 'payer@test.fr');
      final pro = await ts.registerLogin(
          email: 'pro@test.fr', role: 'conducteur', rib: validRib);
      await ts._db.db.insert('transaction_', {
        'montant_centimes': 100,
        'devise': 'EUR',
        'date': DateTime.now().toIso8601String(),
        'statut': 'en_attente',
        'type_service': 'EcoRoute',
        'facture_numero': 'FAC-2026-999999',
        'utilisateur_id': p.$2,
        'beneficiaire_id': pro.$2,
        'moyen_paiement_id': null,
      });

      final (status, body) = await ts.call('DELETE', '/users/me',
          token: p.$1, body: {'mot_de_passe': 'Proxilife2026!'});
      expect(status, 409);
      expect(body['error'], contains('en attente'));
    });

    test('delete account anonymises settled history', () async {
      final p = await ts.registerLogin(email: 'payer@test.fr', solde: 5000);
      final pro = await ts.registerLogin(
          email: 'pro@test.fr', role: 'conducteur', rib: validRib);
      await ts.call('POST', '/payment-methods',
          token: p.$1, body: {'type': 'especes'});
      final (_, tx) = await ts.call('POST', '/transactions',
          token: p.$1,
          body: {
            'montant_centimes': 100,
            'beneficiaire_email': 'pro@test.fr',
            'type_service': 'ServiceNow',
          });
      final txId = tx['id'] as int;

      // Client has 50 € settled balance (wallet untouched) but the solde was
      // only debited for wallet payments; reset for deletion test.
      await ts._db.db.update('utilisateur', {'solde_centimes': 0},
          where: 'id = ?', whereArgs: [p.$2]);

      final (status, _) = await ts.call('DELETE', '/users/me',
          token: p.$1, body: {'mot_de_passe': 'Proxilife2026!'});
      expect(status, 200);

      final row = await ts._db.db
          .query('transaction_', where: 'id = ?', whereArgs: [txId]);
      expect(row.first['utilisateur_id'], isNull);
      // The professional still sees the settled transaction.
      final (invStatus, _) =
          await ts.call('GET', '/transactions/$txId', token: pro.$1);
      expect(invStatus, 200);
    });
  });
}
