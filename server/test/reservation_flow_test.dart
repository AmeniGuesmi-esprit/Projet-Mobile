import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
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

class _Server {
  _Server(this.handler, this.emails, this.db);

  final Handler handler;
  final _FakeEmailSender emails;
  final AppDatabase db;

  static Future<_Server> create() async {
    final db = await AppDatabase.inMemory();
    final emails = _FakeEmailSender();
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
    return _Server(handler, emails, db);
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

  Future<String> login(String email, String role) async {
    await call('POST', '/auth/register', body: {
      'nom': 'Doe',
      'prenom': 'John',
      'email': email,
      'telephone': '0612345678',
      'mot_de_passe': 'Proxilife2026!',
      'role': role,
      if (role == 'conducteur') 'rib': '30004000011234567890173',
    });
    await call('POST', '/auth/verify',
        body: {'email': email, 'code': emails.lastCodeByEmail[email]!});
    final (status, body) = await call('POST', '/auth/login',
        body: {'email': email, 'mot_de_passe': 'Proxilife2026!'});
    if (status != 200) fail('login failed: ${body['error']}');
    return body['token'] as String;
  }

  /// Publishes a trip Hammamet -> Tunis, 2 days from now. Returns its id.
  Future<int> publishTrip(
    String driverToken, {
    int places = 2,
    bool femmes = false,
  }) async {
    final (_, vehicle) = await call('POST', '/vehicles', token: driverToken, body: {
      'marque': 'Peugeot',
      'modele': '208',
      'couleur': 'Gris',
      'nb_places': 4,
    });
    final when = DateTime.now().add(const Duration(days: 2));
    final (status, trip) = await call('POST', '/trips', token: driverToken, body: {
      'vehicule_id': vehicle['id'],
      'depart_adresse': 'Hammamet',
      'depart_latitude': 36.4000,
      'depart_longitude': 10.6167,
      'arrivee_adresse': 'Tunis',
      'arrivee_latitude': 36.8065,
      'arrivee_longitude': 10.1815,
      'date_heure_depart': when.toIso8601String(),
      'places': places,
      'prix_par_place_centimes': 500,
      'ambiance': 'silence',
      'fumeur_accepte': false,
      'animaux_acceptes': false,
      'reserve_aux_femmes': femmes,
    });
    expect(status, 201, reason: '$trip');
    return trip['id'] as int;
  }
}

void main() {
  late _Server server;

  setUp(() async => server = await _Server.create());
  tearDown(() => server.db.close());

  test('request -> accept takes seats, cancel gives them back', () async {
    final driver = await server.login('driver@test.com', 'conducteur');
    final passenger = await server.login('pass@test.com', 'client');
    final tripId = await server.publishTrip(driver, places: 2);

    final (s1, r1) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 2});
    expect(s1, 201, reason: '$r1');
    expect(r1['statut'], 'en_attente');
    expect(r1['montant_centimes'], 1000);

    // Pending: seats are not taken yet.
    var (_, trip) = await server.call('GET', '/trips/$tripId', token: driver);
    expect(trip['places_disponibles'], 2);

    // The driver sees the request.
    final (_, received) =
        await server.call('GET', '/reservations/received', token: driver);
    expect((received['items'] as List).length, 1);

    final id = r1['id'] as int;
    final (s2, r2) =
        await server.call('POST', '/reservations/$id/accept', token: driver);
    expect(s2, 200, reason: '$r2');
    expect(r2['statut'], 'acceptee');

    (_, trip) = await server.call('GET', '/trips/$tripId', token: driver);
    expect(trip['places_disponibles'], 0);
    expect(trip['statut'], 'complet');

    // Already processed.
    final (s3, _) =
        await server.call('POST', '/reservations/$id/accept', token: driver);
    expect(s3, 409);

    // The passenger cancels: seats come back, the trip is open again.
    final (s4, r4) =
        await server.call('POST', '/reservations/$id/cancel', token: passenger);
    expect(s4, 200, reason: '$r4');
    expect(r4['statut'], 'annulee');
    (_, trip) = await server.call('GET', '/trips/$tripId', token: driver);
    expect(trip['places_disponibles'], 2);
    expect(trip['statut'], 'ouvert');
  });

  test('refuse, duplicates and permissions', () async {
    final driver = await server.login('driver@test.com', 'conducteur');
    final passenger = await server.login('pass@test.com', 'client');
    final other = await server.login('other@test.com', 'client');
    final tripId = await server.publishTrip(driver);

    final (_, r1) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 1});
    final id = r1['id'] as int;

    // Second active request on the same trip.
    final (dup, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 1});
    expect(dup, 409);

    // A driver cannot book his own trip.
    final (own, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: driver, body: {'nb_places': 1});
    expect(own, 400);

    // Only the trip's driver can decide; others get 404.
    final (foreign, _) =
        await server.call('POST', '/reservations/$id/accept', token: other);
    expect(foreign, 404);

    // Only the passenger can cancel his reservation.
    final (notMine, _) =
        await server.call('POST', '/reservations/$id/cancel', token: other);
    expect(notMine, 404);

    final (sr, rr) =
        await server.call('POST', '/reservations/$id/refuse', token: driver);
    expect(sr, 200, reason: '$rr');
    expect(rr['statut'], 'refusee');

    // After a refusal the passenger may ask again.
    final (again, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 1});
    expect(again, 201);

    // More seats than available.
    final (tooMany, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: other, body: {'nb_places': 3});
    expect(tooMany, 409);
  });

  test('women-only trips need the declared sex "femme"', () async {
    final driver = await server.login('driver@test.com', 'conducteur');
    final passenger = await server.login('pass@test.com', 'client');
    final tripId = await server.publishTrip(driver, femmes: true);

    final (forbidden, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 1});
    expect(forbidden, 403);

    // Hidden from the search too.
    final (_, hidden) = await server.call(
        'GET', '/trips/search?lat=36.4&lng=10.6167&rayon_km=5',
        token: passenger);
    expect((hidden['items'] as List), isEmpty);

    final (sp, _) = await server.call('PATCH', '/users/me',
        token: passenger, body: {'sexe': 'femme'});
    expect(sp, 200);

    final (_, visible) = await server.call(
        'GET', '/trips/search?lat=36.4&lng=10.6167&rayon_km=5',
        token: passenger);
    expect((visible['items'] as List).length, 1);

    final (ok, _) = await server.call('POST', '/trips/$tripId/reservations',
        token: passenger, body: {'nb_places': 1});
    expect(ok, 201);
  });

  test('proximity search: radius, destination, filters', () async {
    final driver = await server.login('driver@test.com', 'conducteur');
    final passenger = await server.login('pass@test.com', 'client');
    await server.publishTrip(driver);

    Future<int> count(String query) async {
      final (status, body) =
          await server.call('GET', '/trips/search?$query', token: passenger);
      expect(status, 200, reason: '$body');
      return (body['items'] as List).length;
    }

    // From Hammamet itself.
    expect(await count('lat=36.4&lng=10.6167&rayon_km=5'), 1);
    // From Tunis: Hammamet is ~60 km away.
    expect(await count('lat=36.8065&lng=10.1815&rayon_km=10'), 0);
    // Destination close to Tunis / far from Tunis.
    expect(
        await count(
            'lat=36.4&lng=10.6167&rayon_km=5&dest_lat=36.81&dest_lng=10.18'),
        1);
    expect(
        await count(
            'lat=36.4&lng=10.6167&rayon_km=5&dest_lat=35.8&dest_lng=10.6'),
        0);
    // Filters: the trip is silent and non-smoking, no pets.
    expect(await count('lat=36.4&lng=10.6167&ambiance=silence'), 1);
    expect(await count('lat=36.4&lng=10.6167&ambiance=discussion'), 0);
    expect(await count('lat=36.4&lng=10.6167&non_fumeur=1'), 1);
    expect(await count('lat=36.4&lng=10.6167&animaux=1'), 0);
    // Seats and date.
    expect(await count('lat=36.4&lng=10.6167&places=3'), 0);
    final d = DateTime.now().add(const Duration(days: 2));
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    expect(await count('lat=36.4&lng=10.6167&date=$day'), 1);
    expect(await count('lat=36.4&lng=10.6167&date=2020-01-01'), 0);

    // The driver does not see his own trip.
    final (_, own) = await server.call(
        'GET', '/trips/search?lat=36.4&lng=10.6167', token: driver);
    expect((own['items'] as List), isEmpty);
  });
}
