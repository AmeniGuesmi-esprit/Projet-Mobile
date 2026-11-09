import 'dart:convert';
import 'dart:io';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/services/route_planner.dart';
import 'package:proxilife_server/src/services/service_now_geocoder.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeEmailSender implements EmailSender {
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

class _FakeGeocoder implements AddressGeocoder {
  bool down = false;

  @override
  Future<List<GeocodeResultDto>?> search(String query) async => down
      ? null
      : const [
          GeocodeResultDto(
            label: '12 Rue de Marseille, Tunis',
            latitude: 36.8008,
            longitude: 10.1815,
          ),
        ];
}

/// Routing service that is down: tracking must fall back to a straight line.
class _NoRoutes implements RoutePlanner {
  @override
  Future<RouteDto?> route({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required TravelMode mode,
  }) async =>
      null;
}

class _Server {
  _Server(this.handler, this.emails, this.db, this.geocoder);

  final Handler handler;
  final _FakeEmailSender emails;
  final AppDatabase db;
  final _FakeGeocoder geocoder;

  static Future<_Server> create() async {
    final db = await AppDatabase.inMemory();
    final emails = _FakeEmailSender();
    final geocoder = _FakeGeocoder();
    final uploads = Directory.systemTemp.createTempSync('service_now_test');
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
      uploadsDir: uploads.path,
      serviceNowGeocoder: geocoder,
      serviceNowRoutes: _NoRoutes(),
    );
    return _Server(handler, emails, db, geocoder);
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
      raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<String> login(String email, String role) async {
    await call('POST', '/auth/register', body: {
      'nom': 'Doe',
      'prenom': 'John',
      'email': email,
      'telephone': '0612345678',
      'mot_de_passe': 'Proxilife2026!',
      'role': role,
      if (role == 'prestataire') 'rib': '30004000011234567890173',
    });
    await call('POST', '/auth/verify',
        body: {'email': email, 'code': emails.lastCodeByEmail[email]!});
    final (status, body) = await call('POST', '/auth/login',
        body: {'email': email, 'mot_de_passe': 'Proxilife2026!'});
    if (status != 200) fail('login failed: ${body['error']}');
    return body['token'] as String;
  }

  Future<int> createDemande(String token) async {
    final (status, body) =
        await call('POST', '/service-now/demandes', token: token, body: {
      'type': 'plomberie',
      'description': 'Fuite importante sous l\'évier',
      'adresse': '12 rue de Marseille, Tunis',
      'date_souhaitee': _inDays(2),
    });
    expect(status, 201, reason: '$body');
    return body['id'] as int;
  }

  Future<int> accept(String token, int demandeId, {int prix = 4500}) async {
    final (status, body) = await call(
      'POST',
      '/service-now/demandes/$demandeId/accepter',
      token: token,
      body: {'date_prevue': _inDays(3), 'prix_centimes': prix},
    );
    expect(status, 201, reason: '$body');
    return (body['intervention'] as Map<String, dynamic>)['id'] as int;
  }

  /// The code only the client can see.
  Future<String> presenceCode(String clientToken, int demandeId) async {
    final (_, body) = await call('GET', '/service-now/demandes/$demandeId',
        token: clientToken);
    return (body['intervention'] as Map<String, dynamic>)['qr_code'] as String;
  }

  Future<void> begin(
    String token,
    String clientToken,
    int demandeId,
    int interventionId,
  ) async {
    final code = await presenceCode(clientToken, demandeId);
    final (started, body) = await call(
      'POST',
      '/service-now/interventions/$interventionId/demarrer',
      token: token,
      body: {'qr_code': code},
    );
    expect(started, 200, reason: '$body');
  }

  Future<void> finish(
    String token,
    String clientToken,
    int demandeId,
    int interventionId,
  ) async {
    await begin(token, clientToken, demandeId, interventionId);
    final (finished, body) = await call(
      'POST',
      '/service-now/interventions/$interventionId/terminer',
      token: token,
      body: {'rapport': 'Joint remplacé, fuite réparée'},
    );
    expect(finished, 200, reason: '$body');
  }

  Future<int> balanceOf(String email) async {
    final rows = await db.db.query('utilisateur',
        columns: ['solde_centimes'], where: 'email = ?', whereArgs: [email]);
    return rows.first['solde_centimes'] as int;
  }

  Future<void> giveWallet(String token, String email, int centimes) async {
    final (status, _) = await call('POST', '/payment-methods',
        token: token, body: {'type': 'portefeuille'});
    expect(status, 201);
    await db.db.update('utilisateur', {'solde_centimes': centimes},
        where: 'email = ?', whereArgs: [email]);
  }
}

String _inDays(int days) =>
    DateTime.now().add(Duration(days: days)).toUtc().toIso8601String();

void main() {
  late _Server server;
  late String client;
  late String prestataire;

  setUp(() async {
    server = await _Server.create();
    client = await server.login('client@test.tn', 'client');
    prestataire = await server.login('prestataire@test.tn', 'prestataire');
  });
  tearDown(() => server.db.close());

  test('full path: request, acceptance, work, payment', () async {
    await server.giveWallet(client, 'client@test.tn', 10000);
    final demandeId = await server.createDemande(client);

    var (status, list) = await server.call(
        'GET', '/service-now/demandes/disponibles',
        token: prestataire);
    expect(status, 200);
    expect(list['items'], hasLength(1));

    final interventionId = await server.accept(prestataire, demandeId);

    (status, list) = await server.call(
        'GET', '/service-now/demandes/disponibles',
        token: prestataire);
    expect(list['items'], isEmpty);

    await server.finish(prestataire, client, demandeId, interventionId);

    final (paid, body) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/payer',
      token: client,
      body: {},
    );
    expect(paid, 200, reason: '$body');
    expect(body['statut'], 'terminee');
    final intervention = body['intervention'] as Map<String, dynamic>;
    expect(intervention['paiement_statut'], 'paye');
    expect(intervention['rapport'], 'Joint remplacé, fuite réparée');
    expect(await server.balanceOf('client@test.tn'), 5500);
    expect(await server.balanceOf('prestataire@test.tn'), 4500);

    final (again, _) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/payer',
      token: client,
      body: {},
    );
    expect(again, 409);
    expect(await server.balanceOf('client@test.tn'), 5500);
  });

  test('roles are enforced', () async {
    final other = await server.login('other@test.tn', 'client');
    final demandeId = await server.createDemande(client);

    var result = await server.call('POST', '/service-now/demandes',
        token: prestataire,
        body: {
          'type': 'menage',
          'description': 'Un prestataire ne demande rien',
          'adresse': 'Tunis',
          'date_souhaitee': _inDays(1),
        });
    expect(result.$1, 403);

    result = await server.call('GET', '/service-now/demandes/disponibles',
        token: client);
    expect(result.$1, 403);

    result = await server.call(
      'POST',
      '/service-now/demandes/$demandeId/accepter',
      token: client,
      body: {'date_prevue': _inDays(3), 'prix_centimes': 1000},
    );
    expect(result.$1, 403);

    result = await server.call('POST', '/service-now/demandes/$demandeId/annuler',
        token: other);
    expect(result.$1, 403);

    result =
        await server.call('GET', '/service-now/demandes/$demandeId', token: other);
    expect(result.$1, 403);
  });

  test('invalid input is rejected by the server', () async {
    Future<int> post(Map<String, dynamic> body) async {
      final (status, _) = await server.call('POST', '/service-now/demandes',
          token: client, body: body);
      return status;
    }

    final valid = {
      'type': 'plomberie',
      'description': 'Fuite importante sous l\'évier',
      'adresse': 'Tunis',
      'date_souhaitee': _inDays(1),
    };
    expect(await post({...valid, 'type': 'inconnu'}), 400);
    expect(await post({...valid, 'description': 'court'}), 400);
    expect(await post({...valid, 'adresse': ' '}), 400);
    expect(await post({...valid, 'date_souhaitee': _inDays(-1)}), 400);
    expect(await post({...valid, 'date_souhaitee': 'demain'}), 400);
    expect(await post(valid), 201);
  });

  test('a request can only be taken once', () async {
    final second = await server.login('second@test.tn', 'prestataire');
    final demandeId = await server.createDemande(client);
    await server.accept(prestataire, demandeId);

    final (status, _) = await server.call(
      'POST',
      '/service-now/demandes/$demandeId/accepter',
      token: second,
      body: {'date_prevue': _inDays(3), 'prix_centimes': 1000},
    );
    expect(status, 409);
  });

  test('phone numbers are shared only after acceptance', () async {
    final demandeId = await server.createDemande(client);
    var (_, list) = await server.call(
        'GET', '/service-now/demandes/disponibles',
        token: prestataire);
    final open = (list['items'] as List).first as Map<String, dynamic>;
    expect(open['client_telephone'], isNull);
    expect(open['client_nom'], 'John D.');

    await server.accept(prestataire, demandeId);
    final (_, seen) = await server.call(
        'GET', '/service-now/demandes/$demandeId',
        token: prestataire);
    expect(seen['client_telephone'], '0612345678');
    expect(seen['client_nom'], 'John Doe');
  });

  test('only a waiting request can be edited', () async {
    final demandeId = await server.createDemande(client);
    var (status, body) = await server.call(
      'PATCH',
      '/service-now/demandes/$demandeId',
      token: client,
      body: {'adresse': 'Nouvelle adresse, Sfax'},
    );
    expect(status, 200, reason: '$body');
    expect(body['adresse'], 'Nouvelle adresse, Sfax');
    expect(body['type'], 'plomberie');

    await server.accept(prestataire, demandeId);
    (status, body) = await server.call(
      'PATCH',
      '/service-now/demandes/$demandeId',
      token: client,
      body: {'adresse': 'Trop tard'},
    );
    expect(status, 409);
  });

  test('withdrawing returns the request to the list', () async {
    final second = await server.login('second@test.tn', 'prestataire');
    final demandeId = await server.createDemande(client);
    final first = await server.accept(prestataire, demandeId);

    final (status, body) = await server.call(
        'POST', '/service-now/interventions/$first/desister',
        token: prestataire);
    expect(status, 200, reason: '$body');
    expect(body['statut'], 'en_attente');
    expect(body['intervention'], isNull);

    await server.accept(second, demandeId);
    final (_, mine) = await server.call(
        'GET', '/service-now/interventions/mine',
        token: prestataire);
    expect(mine['items'], isEmpty);
  });

  test('cancellation stops the planned intervention, not work in progress',
      () async {
    final planned = await server.createDemande(client);
    await server.accept(prestataire, planned);
    var (status, body) = await server.call(
        'POST', '/service-now/demandes/$planned/annuler',
        token: client);
    expect(status, 200, reason: '$body');
    expect(body['statut'], 'annulee');
    expect((body['intervention'] as Map)['statut'], 'annulee');

    final started = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, started);
    await server.begin(prestataire, client, started, interventionId);
    (status, body) = await server.call(
        'POST', '/service-now/demandes/$started/annuler',
        token: client);
    expect(status, 409);
  });

  test('an intervention cannot be finished before starting', () async {
    final demandeId = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, demandeId);
    final (status, _) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/terminer',
      token: prestataire,
      body: {'rapport': 'Travail réalisé'},
    );
    expect(status, 409);
  });

  test('a payment with an empty wallet fails and can be retried', () async {
    await server.giveWallet(client, 'client@test.tn', 100);
    final demandeId = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, demandeId);
    await server.finish(prestataire, client, demandeId, interventionId);

    var (status, body) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/payer',
      token: client,
      body: {},
    );
    expect(status, 402, reason: '$body');
    expect(await server.balanceOf('prestataire@test.tn'), 0);

    await server.db.db.update('utilisateur', {'solde_centimes': 9000},
        where: 'email = ?', whereArgs: ['client@test.tn']);
    (status, body) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/payer',
      token: client,
      body: {},
    );
    expect(status, 200, reason: '$body');
    expect(await server.balanceOf('prestataire@test.tn'), 4500);
  });

  test('the presence code is required and only the client sees it', () async {
    final demandeId = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, demandeId);

    final (_, seen) = await server.call(
        'GET', '/service-now/demandes/$demandeId',
        token: prestataire);
    expect((seen['intervention'] as Map)['qr_code'], isNull);

    final (wrong, _) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/demarrer',
      token: prestataire,
      body: {'qr_code': 'FAUXCODE'},
    );
    expect(wrong, 400);

    await server.begin(prestataire, client, demandeId, interventionId);
  });

  test('rating happens once, after paying, and feeds the average', () async {
    await server.giveWallet(client, 'client@test.tn', 10000);
    final demandeId = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, demandeId);
    await server.finish(prestataire, client, demandeId, interventionId);

    Future<int> rate() async {
      final (status, _) = await server.call(
        'POST',
        '/service-now/interventions/$interventionId/evaluer',
        token: client,
        body: {'note': 4, 'commentaire': 'Rapide et propre'},
      );
      return status;
    }

    expect(await rate(), 409, reason: 'not paid yet');
    await server.call(
      'POST',
      '/service-now/interventions/$interventionId/payer',
      token: client,
      body: {},
    );
    expect(await rate(), 200);
    expect(await rate(), 409, reason: 'already rated');

    final (_, seen) = await server.call(
        'GET', '/service-now/demandes/$demandeId',
        token: client);
    final intervention = seen['intervention'] as Map<String, dynamic>;
    expect(intervention['note'], 4);
    expect(intervention['prestataire_note_moyenne'], 4);
    expect(intervention['prestataire_nb_notes'], 1);
  });

  test('smart matching ranks by specialty and distance', () async {
    Future<int> demande(String type, double lat, double lng) async {
      final (status, body) =
          await server.call('POST', '/service-now/demandes', token: client, body: {
        'type': type,
        'description': 'Besoin d\'une intervention rapide',
        'adresse': 'Tunis',
        'date_souhaitee': _inDays(2),
        'latitude': lat,
        'longitude': lng,
      });
      expect(status, 201, reason: '$body');
      return body['id'] as int;
    }

    final farOther = await demande('menage', 37.27, 9.87);
    final nearSpecialty = await demande('plomberie', 36.80, 10.18);

    final (saved, _) = await server.call('PUT', '/service-now/profil',
        token: prestataire,
        body: {
          'specialites': ['plomberie'],
          'latitude': 36.81,
          'longitude': 10.17,
        });
    expect(saved, 200);

    final (_, list) = await server.call(
        'GET', '/service-now/demandes/disponibles',
        token: prestataire);
    final items = (list['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((e) => e['id']), [nearSpecialty, farOther]);
    expect(items.first['specialite_correspond'], isTrue);
    expect(items.first['distance_km'], lessThan(5));

    final (status, nearby) = await server.call(
        'GET', '/service-now/demandes/$nearSpecialty/prestataires',
        token: client);
    expect(status, 200);
    final first = (nearby['items'] as List).first as Map<String, dynamic>;
    expect(first['specialiste'], isTrue);
    expect(first.containsKey('telephone'), isFalse);
  });

  test('the estimate uses past prices once there are enough', () async {
    Future<Map<String, dynamic>> estimate() async {
      final (_, body) = await server.call(
          'GET', '/service-now/estimation?type=plomberie',
          token: client);
      return body;
    }

    expect((await estimate())['based_on'], 0);
    for (final price in [2000, 4000, 6000]) {
      final demandeId = await server.createDemande(client);
      final interventionId =
          await server.accept(prestataire, demandeId, prix: price);
      await server.finish(prestataire, client, demandeId, interventionId);
    }
    final result = await estimate();
    expect(result['based_on'], 3);
    expect(result['min_centimes'], 2000);
    expect(result['max_centimes'], 4000);
  });

  test('tracking stops at the start and survives a routing failure', () async {
    final (_, created) =
        await server.call('POST', '/service-now/demandes', token: client, body: {
      'type': 'plomberie',
      'description': 'Fuite importante sous l\'évier',
      'adresse': 'Tunis',
      'date_souhaitee': _inDays(2),
      'latitude': 36.80,
      'longitude': 10.18,
    });
    final demandeId = created['id'] as int;
    final interventionId = await server.accept(prestataire, demandeId);

    final (left, _) = await server.call(
      'POST',
      '/service-now/interventions/$interventionId/en-route',
      token: prestataire,
      body: {'latitude': 36.85, 'longitude': 10.2},
    );
    expect(left, 200);

    var (status, track) = await server.call(
        'GET', '/service-now/interventions/$interventionId/suivi',
        token: client);
    expect(status, 200);
    expect(track['en_route'], isTrue);
    expect(track['approximatif'], isTrue);
    expect(track['duree_secondes'], greaterThan(0));

    await server.begin(prestataire, client, demandeId, interventionId);
    (status, track) = await server.call(
        'GET', '/service-now/interventions/$interventionId/suivi',
        token: client);
    expect(track['en_route'], isFalse);
    expect(track['latitude'], isNull);
  });

  test('photos are added during the work and served to participants', () async {
    final other = await server.login('other@test.tn', 'client');
    final demandeId = await server.createDemande(client);
    final interventionId = await server.accept(prestataire, demandeId);
    final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

    Future<int> upload() async {
      final (status, _) = await server.call(
        'POST',
        '/service-now/interventions/$interventionId/photos',
        token: prestataire,
        body: {'type': 'avant', 'photo_base64': jpeg},
      );
      return status;
    }

    expect(await upload(), 409);
    await server.begin(prestataire, client, demandeId, interventionId);
    expect(await upload(), 200);

    Future<int> read(String token) async {
      final response = await server.handler(Request(
        'GET',
        Uri.parse('http://test/service-now/interventions/$interventionId'
            '/photos/avant'),
        headers: {'authorization': 'Bearer $token'},
      ));
      return response.statusCode;
    }

    expect(await read(client), 200);
    expect(await read(other), 403);
  });

  test('notifications reach the right person, once', () async {
    Future<List<String>> take(String token) async {
      final (_, body) = await server.call(
          'POST', '/service-now/notifications/nouvelles',
          token: token);
      return [
        for (final item in body['items'] as List)
          (item as Map<String, dynamic>)['titre'] as String,
      ];
    }

    await server.call('PUT', '/service-now/profil',
        token: prestataire, body: {'specialites': ['plomberie']});

    final demandeId = await server.createDemande(client);
    expect(await take(prestataire), ['Nouvelle demande : Plomberie']);
    expect(await take(prestataire), isEmpty);

    await server.accept(prestataire, demandeId);
    expect(await take(client), ['Demande acceptée']);
    expect(await take(prestataire), isEmpty);

    await server.call('POST', '/service-now/demandes/$demandeId/annuler',
        token: client);
    expect(await take(prestataire), ['Demande annulée']);
  });

  test('the calendar blocks days off and overlapping work', () async {
    final demandeId = await server.createDemande(client);
    final dayOff = DateTime.now().add(const Duration(days: 3));

    var (status, body) = await server.call(
      'PUT',
      '/service-now/disponibilites',
      token: prestataire,
      body: {
        'creneaux': <Object>[],
        'jours_off': [ServiceNowRules.dayKey(dayOff)],
      },
    );
    expect(status, 200, reason: '$body');

    (status, body) = await server.call(
      'POST',
      '/service-now/demandes/$demandeId/accepter',
      token: prestataire,
      body: {'date_prevue': _inDays(3), 'prix_centimes': 1000},
    );
    expect(status, 409, reason: '$body');

    await server.call('PUT', '/service-now/disponibilites',
        token: prestataire,
        body: {'creneaux': <Object>[], 'jours_off': <Object>[]});
    await server.accept(prestataire, demandeId);

    final other = await server.createDemande(client);
    (status, body) = await server.call(
      'POST',
      '/service-now/demandes/$other/accepter',
      token: prestataire,
      body: {'date_prevue': _inDays(3), 'prix_centimes': 1000},
    );
    expect(status, 409, reason: 'overlaps the first intervention');
  });

  test('recommendations skip an unavailable prestataire', () async {
    final demandeId = await server.createDemande(client);
    Future<int> count() async {
      final (_, body) = await server.call(
          'GET', '/service-now/demandes/$demandeId/prestataires',
          token: client);
      return (body['items'] as List).length;
    }

    expect(await count(), 1);
    final wanted = DateTime.now().add(const Duration(days: 2));
    await server.call('PUT', '/service-now/disponibilites',
        token: prestataire,
        body: {
          'creneaux': <Object>[],
          'jours_off': [ServiceNowRules.dayKey(wanted)],
        });
    expect(await count(), 0);
  });

  test('invalid calendars are rejected', () async {
    final (status, _) = await server.call(
      'PUT',
      '/service-now/disponibilites',
      token: prestataire,
      body: {
        'creneaux': [
          {'jour': 1, 'debut_minutes': 600, 'fin_minutes': 500},
        ],
        'jours_off': <Object>[],
      },
    );
    expect(status, 400);
  });

  test('chat is limited to the two people on the job', () async {
    final other = await server.login('other@test.tn', 'client');
    final demandeId = await server.createDemande(client);
    final path = '/service-now/demandes/$demandeId/messages';

    var (status, body) = await server.call('POST', path,
        token: client, body: {'contenu': 'Bonjour ?'});
    expect(status, 403, reason: 'no prestataire yet');

    await server.accept(prestataire, demandeId);
    await server.call('POST', '/service-now/notifications/nouvelles',
        token: client);

    (status, body) = await server.call('POST', path,
        token: client, body: {'contenu': 'Bonjour, à quelle heure ?'});
    expect(status, 200, reason: '$body');
    expect(body['items'], hasLength(1));

    (status, body) = await server.call('POST', path,
        token: prestataire, body: {'contenu': 'Vers 10 h.'});
    expect(body['items'], hasLength(2));

    final (_, inbox) = await server.call(
        'POST', '/service-now/notifications/nouvelles',
        token: client);
    expect((inbox['items'] as List).first['message'], 'Vers 10 h.');

    (status, body) = await server.call('GET', path, token: other);
    expect(status, 403);

    (status, body) = await server.call('POST', path,
        token: client, body: {'contenu': '   '});
    expect(status, 400);
  });

  test('address search reports an unavailable service', () async {
    var (status, body) = await server.call(
        'GET', '/service-now/adresses?q=Marseille',
        token: client);
    expect(status, 200);
    expect(body['items'], hasLength(1));

    server.geocoder.down = true;
    (status, body) = await server.call(
        'GET', '/service-now/adresses?q=Sfax',
        token: client);
    expect(status, 503);
  });
}
