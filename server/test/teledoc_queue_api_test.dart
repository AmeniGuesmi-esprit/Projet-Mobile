import 'package:test/test.dart';

import 'teledoc_test_support.dart';

void main() {
  late TeledocTestServer server;
  // Controlled clock: arrival order and consultation lengths are exact.
  late DateTime now;
  late List<String> patients;
  late String doctorA;
  late String doctorB;

  setUp(() async {
    now = DateTime(2026, 10, 14, 9);
    server = await TeledocTestServer.create(clock: () => now);
    patients = [
      for (var i = 0; i < 4; i++)
        (await server.user('p$i@test.tn', 'client')).$2,
    ];
    (_, doctorA) = await server.user('a@test.tn', 'medecin');
    (_, doctorB) = await server.user('b@test.tn', 'medecin');
  });
  tearDown(() => server.close());

  /// Patient [index] creates a request one minute after the previous one.
  Future<int> request(int index, String urgence) async {
    now = now.add(const Duration(minutes: 1));
    final (status, body) = await server.call('POST', '/teledoc/requests',
        body: validRequestBody(urgence: urgence), token: patients[index]);
    expect(status, 201, reason: '$body');
    return body['id'] as int;
  }

  Future<Map<String, dynamic>> queueStatus(int index, int id) async {
    final (status, body) = await server.call(
        'GET', '/teledoc/requests/$id/queue-status',
        token: patients[index]);
    expect(status, 200, reason: '$body');
    return body;
  }

  Future<(int, Map<String, dynamic>)> start(String doctor,
          {String type = 'video'}) =>
      server.call('POST', '/teledoc/consultations',
          body: {'type': type}, token: doctor);

  test('position et temps estimé : 2 médecins, 15 min par défaut', () async {
    final ids = [
      await request(0, 'faible'),
      await request(1, 'faible'),
      await request(2, 'faible'),
    ];
    final s = [for (var i = 0; i < 3; i++) await queueStatus(i, ids[i])];
    expect(s.map((e) => e['position_file']), [1, 2, 3]);
    // ⌊(p − 1) / 2⌋ × 15
    expect(s.map((e) => e['temps_estime_minutes']), [0, 0, 15]);
    expect(s.first['taille_file'], 3);
    expect(s.first['statut'], 'en_attente');

    // The request DTO carries the same derived values.
    final (_, dto) = await server.call('GET', '/teledoc/requests/${ids[2]}',
        token: patients[2]);
    expect(dto['position_file'], 3);
    expect(dto['temps_estime_minutes'], 15);
  });

  test('un compte médecin suspendu ne compte pas', () async {
    await insertTestUser(server.db, 'off@test.tn', 'medecin',
        statut: 'suspendu');
    await request(0, 'faible');
    await request(1, 'faible');
    final id = await request(2, 'faible');
    expect((await queueStatus(2, id))['temps_estime_minutes'], 15);
  });

  test('temps dynamique : une urgence passe devant', () async {
    await request(0, 'faible');
    final late = await request(1, 'faible');
    expect((await queueStatus(1, late))['position_file'], 2);

    final urgent = await request(2, 'elevee');
    expect((await queueStatus(2, urgent))['position_file'], 1);
    expect((await queueStatus(1, late))['position_file'], 3);
  });

  test('temps dynamique : une annulation fait avancer la file', () async {
    final first = await request(0, 'moyenne');
    await request(1, 'moyenne');
    final last = await request(2, 'moyenne');
    expect((await queueStatus(2, last))['position_file'], 3);

    await server.call('POST', '/teledoc/requests/$first/cancel',
        token: patients[0]);
    final after = await queueStatus(2, last);
    expect(after['position_file'], 2);
    expect(after['taille_file'], 2);
  });

  test('passer en urgence élevée (modification) fait avancer', () async {
    await request(0, 'faible');
    final id = await request(1, 'faible');
    await server.call('PATCH', '/teledoc/requests/$id',
        body: {'urgence': 'elevee'}, token: patients[1]);
    expect((await queueStatus(1, id))['position_file'], 1);
  });

  group('Démarrer une consultation (tête de file)', () {
    test('le médecin prend la tête, la file avance pour les autres', () async {
      final normal = await request(0, 'moyenne');
      final urgent = await request(1, 'elevee');
      final waiting = await request(2, 'faible');

      final (status, consultation) = await start(doctorA, type: 'audio');
      expect(status, 201);
      expect(consultation['id_demande'], urgent, reason: 'urgence d\'abord');
      expect(consultation['type'], 'audio');
      expect(consultation['statut_demande'], 'en_cours');

      final started = await queueStatus(1, urgent);
      expect(started['statut'], 'en_cours');
      expect(started['position_file'], isNull);
      expect(started['consultation_id'], consultation['id']);
      expect(started['type_consultation'], 'audio');

      expect((await queueStatus(0, normal))['position_file'], 1);
      expect((await queueStatus(2, waiting))['position_file'], 2);

      final (_, second) = await start(doctorB);
      expect(second['id_demande'], normal);
    });

    test('un seul appel en cours par médecin', () async {
      await request(0, 'faible');
      await request(1, 'faible');
      await start(doctorA);
      final (status, body) = await start(doctorA);
      expect(status, 409);
      expect(body['error'], contains('déjà une consultation en cours'));
    });

    test('file vide : 404 ; type invalide : 400 ; patient : 403', () async {
      final (empty, _) = await start(doctorA);
      expect(empty, 404);
      await request(0, 'faible');
      final (badType, _) = await start(doctorA, type: 'chat');
      expect(badType, 400);
      final (asPatient, _) = await server.call('POST', '/teledoc/consultations',
          body: {'type': 'video'}, token: patients[1]);
      expect(asPatient, 403);
    });

    test('deux médecins en même temps ne prennent jamais la même demande',
        () async {
      await request(0, 'faible');
      final results = await Future.wait([start(doctorA), start(doctorB)]);
      final statuses = results.map((r) => r.$1).toList()..sort();
      expect(statuses, [201, 404]);
    });

    test('consultation supprimée : la demande retrouve sa place', () async {
      final first = await request(0, 'moyenne');
      final second = await request(1, 'moyenne');
      final (_, c) = await start(doctorA);
      expect(c['id_demande'], first);
      expect((await queueStatus(1, second))['position_file'], 1);

      await server.call('DELETE', '/teledoc/consultations/${c['id']}',
          token: doctorA);
      expect((await queueStatus(0, first))['position_file'], 1,
          reason: 'date de création d\'origine conservée');
      expect((await queueStatus(1, second))['position_file'], 2);
    });
  });

  test('durée moyenne dynamique : alimentée par les consultations réelles',
      () async {
    final ids = [
      await request(0, 'faible'),
      await request(1, 'faible'),
      await request(2, 'faible'),
      await request(3, 'faible'),
    ];
    // Two consultations of 30 min each.
    for (final doctor in [doctorA, doctorB]) {
      final (_, c) = await start(doctor);
      now = now.add(const Duration(minutes: 30));
      await server.call('POST', '/teledoc/consultations/${c['id']}/end',
          body: {'ordonnance': 'Repos'}, token: doctor);
    }
    // Remaining: ids[2] (position 1), ids[3] (position 2) — 2 doctors.
    final s = await queueStatus(3, ids[3]);
    expect(s['position_file'], 2);
    expect(s['temps_estime_minutes'], 0);

    final newcomer = await request(0, 'faible');
    final n = await queueStatus(0, newcomer);
    expect(n['position_file'], 3);
    expect(n['temps_estime_minutes'], 30, reason: '⌊2/2⌋ × 30 min');
  });

  group('Accès à la file', () {
    test('médecin : file triée avec positions', () async {
      await request(0, 'faible');
      await request(1, 'elevee');
      final (status, body) =
          await server.call('GET', '/teledoc/queue', token: doctorA);
      expect(status, 200);
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((i) => i['urgence']), ['elevee', 'faible']);
      expect(items.map((i) => i['position_file']), [1, 2]);
    });

    test('patient : pas d\'accès à la file des autres', () async {
      final id = await request(0, 'faible');
      final (queue, _) =
          await server.call('GET', '/teledoc/queue', token: patients[0]);
      expect(queue, 403);
      final (other, _) = await server.call(
          'GET', '/teledoc/requests/$id/queue-status',
          token: patients[1]);
      expect(other, 404);
    });
  });
}
