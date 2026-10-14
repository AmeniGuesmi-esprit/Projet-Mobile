import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'teledoc_test_support.dart';

void main() {
  late TeledocTestServer server;
  late int patientId;
  late String patient;
  late String otherPatient;
  late int doctorId;
  late String doctor;
  late String otherDoctor;

  setUp(() async {
    server = await TeledocTestServer.create();
    (patientId, patient) =
        await server.user('patient@test.tn', 'client', prenom: 'Ameni');
    (_, otherPatient) = await server.user('autre@test.tn', 'client');
    (doctorId, doctor) = await server.user('dr@test.tn', 'medecin');
    (_, otherDoctor) = await server.user('dr2@test.tn', 'medecin');
  });
  tearDown(() => server.close());

  Future<int> createRequest({String? photo, String token = ''}) async {
    final (status, body) = await server.call('POST', '/teledoc/requests',
        body: validRequestBody(photo: photo),
        token: token.isEmpty ? patient : token);
    expect(status, 201, reason: '$body');
    return body['id'] as int;
  }

  /// Puts a request in consultation directly in SQL (starting a consultation
  /// from the queue is covered by the queue tests).
  Future<int> startConsultation(int requestId, {int? medecinId}) async {
    await server.db.update('teledoc_demande', {'statut': 'en_cours'},
        where: 'id = ?', whereArgs: [requestId]);
    return server.db.insert('teledoc_consultation', {
      'date_debut': DateTime.now().toIso8601String(),
      'type': 'video',
      'demande_id': requestId,
      'medecin_id': medecinId ?? doctorId,
    });
  }

  group('Créer une demande', () {
    test('avec photo : 201, payée 30 DT, photo stockée', () async {
      final (status, body) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody(photo: fakeJpegBase64), token: patient);
      expect(status, 201);
      expect(body['statut'], 'en_attente');
      expect(body['a_photo'], isTrue);
      expect(body['patient_nom'], 'Ameni Utilisateur');
      expect(body.containsKey('photo_symptome'), isFalse,
          reason: 'le nom de fichier ne doit jamais sortir');
      final id = body['id'] as int;
      expect(body['transaction_id'], 1000 + id);
      expect(server.payments.charges.single,
          (patientId: patientId, amountCents: 3000, requestId: id));
      expect(server.storedPhotos(), hasLength(1));
      expect(server.storedPhotos().single, matches(r'^[0-9a-f]{32}\.jpg$'));
    });

    test('validation côté serveur (messages en français)', () async {
      Future<(int, Map<String, dynamic>)> post(Map<String, dynamic> body) =>
          server.call('POST', '/teledoc/requests', body: body, token: patient);

      var (status, body) = await post({...validRequestBody(), 'motif': 'ab'});
      expect(status, 400);
      expect(body['error'], contains('au moins 3'));

      (status, body) = await post({...validRequestBody(), 'urgence': 'max'});
      expect(status, 400);
      expect(body['error'], contains('Urgence invalide'));

      (status, body) = await post({...validRequestBody(), 'motif': 42});
      expect(status, 400);
      expect(body['error'], contains('doit être un texte'));

      (status, body) = await post({'urgence': 'faible'});
      expect((status, body['error']), (400, 'Motif obligatoire'));
      expect(server.payments.charges, isEmpty);
    });

    test('photo : signature, taille et encodage vérifiés', () async {
      Future<String> error(String photo) async {
        final (status, body) = await server.call('POST', '/teledoc/requests',
            body: validRequestBody(photo: photo), token: patient);
        expect(status, 400);
        return body['error'] as String;
      }

      expect(await error(fakeGifBase64), contains('JPEG ou PNG'));
      expect(await error('pas du base64 !!'), contains('base64'));
      final tooBig =
          base64.encode([0xFF, 0xD8, 0xFF, ...List.filled(2 * 1024 * 1024, 0)]);
      expect(await error(tooBig), contains('2 Mo'));
      expect(server.storedPhotos(), isEmpty);
    });

    test('réservé aux patients', () async {
      final (status, _) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody(), token: doctor);
      expect(status, 403);
      final (_, conducteur) = await server.user('c@test.tn', 'conducteur');
      final (status2, body2) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody(), token: conducteur);
      expect(status2, 403);
      expect(body2['error'], contains('réservé aux patients et aux médecins'));
    });

    test('sans jeton : 401', () async {
      final (status, _) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody());
      expect(status, 401);
    });

    test('une seule demande active par patient', () async {
      await createRequest();
      final (status, body) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody(), token: patient);
      expect(status, 409);
      expect(body['error'], contains('déjà une demande en cours'));
    });

    test('paiement refusé : 402, rien n\'est mis en file', () async {
      server.payments.declineCharges = true;
      final (status, body) = await server.call('POST', '/teledoc/requests',
          body: validRequestBody(photo: fakePngBase64), token: patient);
      expect(status, 402);
      expect(body['error'], 'Solde insuffisant');
      expect(await server.db.query('teledoc_demande'), isEmpty);
      expect(server.storedPhotos(), isEmpty, reason: 'photo nettoyée');
    });

    test('mock par défaut : id de transaction fictif négatif', () async {
      final database = await AppDatabase.inMemory();
      final sessions = SessionService(database.db, UserRepository(database.db));
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
        logRequestsMiddleware: false,
      );
      final id = await insertTestUser(database.db, 'm@test.tn', 'client');
      final token = await sessions.createSession(id);
      // Without a photo nothing is written to uploads/ during tests.
      final response = await handler(Request(
        'POST',
        Uri.parse('http://test/teledoc/requests'),
        body: jsonEncode(validRequestBody()),
        headers: {'authorization': 'Bearer $token'},
      ));
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(response.statusCode, 201, reason: 'module monté dans buildApp');
      expect(body['transaction_id'], -(body['id'] as int));
      await database.close();
    });
  });

  group('Consulter', () {
    test('un patient ne voit que ses demandes', () async {
      final id = await createRequest();
      final (status, _) = await server.call('GET', '/teledoc/requests/$id',
          token: otherPatient);
      expect(status, 404);
      final (_, list) =
          await server.call('GET', '/teledoc/requests', token: otherPatient);
      expect(list['items'], isEmpty);
      final (_, mine) =
          await server.call('GET', '/teledoc/requests', token: patient);
      expect((mine['items'] as List).single['id'], id);
    });

    test('filtre par statut, statut inconnu refusé', () async {
      await createRequest();
      final (_, waiting) = await server
          .call('GET', '/teledoc/requests?statut=en_attente', token: patient);
      expect(waiting['items'], hasLength(1));
      final (_, done) = await server
          .call('GET', '/teledoc/requests?statut=terminee', token: patient);
      expect(done['items'], isEmpty);
      final (status, _) = await server
          .call('GET', '/teledoc/requests?statut=bidon', token: patient);
      expect(status, 400);
    });

    test('photo : servie au patient et au médecin, pas aux autres', () async {
      final id = await createRequest(photo: fakePngBase64);
      final ok = await server.raw('GET', '/teledoc/requests/$id/photo',
          token: patient);
      expect(ok.statusCode, 200);
      expect(ok.headers['content-type'], 'image/png');
      expect(ok.headers['cache-control'], 'private, no-store');
      expect((await ok.read().expand((b) => b).toList()).take(4),
          [0x89, 0x50, 0x4E, 0x47]);

      final asDoctor =
          await server.raw('GET', '/teledoc/requests/$id/photo', token: doctor);
      expect(asDoctor.statusCode, 200, reason: 'demande en file');

      final other = await server.raw('GET', '/teledoc/requests/$id/photo',
          token: otherPatient);
      expect(other.statusCode, 404);
    });

    test('médecin : voit une demande qu\'il traite, pas celle d\'un confrère',
        () async {
      final id = await createRequest();
      await startConsultation(id);
      final (mine, _) =
          await server.call('GET', '/teledoc/requests/$id', token: doctor);
      expect(mine, 200);
      final (theirs, _) =
          await server.call('GET', '/teledoc/requests/$id', token: otherDoctor);
      expect(theirs, 404);
      final (list, _) =
          await server.call('GET', '/teledoc/requests', token: doctor);
      expect(list, 403, reason: 'le médecin passe par la file');
    });
  });

  group('Modifier une demande', () {
    test('en attente : champs modifiés, ancienne photo supprimée', () async {
      final id = await createRequest(photo: fakeJpegBase64);
      final before = server.storedPhotos().single;
      final (status, body) = await server.call(
        'PATCH',
        '/teledoc/requests/$id',
        body: {'urgence': 'elevee', 'photo_base64': fakePngBase64},
        token: patient,
      );
      expect(status, 200);
      expect(body['urgence'], 'elevee');
      expect(server.storedPhotos().single, isNot(before));
      expect(server.storedPhotos().single, endsWith('.png'));

      final (_, removed) = await server.call('PATCH', '/teledoc/requests/$id',
          body: {'supprimer_photo': true}, token: patient);
      expect(removed['a_photo'], isFalse);
      expect(server.storedPhotos(), isEmpty);
    });

    test('corps vide ou invalide : 400', () async {
      final id = await createRequest();
      final (empty, _) = await server.call('PATCH', '/teledoc/requests/$id',
          body: <String, dynamic>{}, token: patient);
      expect(empty, 400);
      final (bad, body) = await server.call('PATCH', '/teledoc/requests/$id',
          body: {'description': 'court'}, token: patient);
      expect(bad, 400);
      expect(body['error'], contains('au moins 10'));
    });

    test('impossible une fois la consultation commencée', () async {
      final id = await createRequest();
      await startConsultation(id);
      final (status, body) = await server.call('PATCH', '/teledoc/requests/$id',
          body: {'motif': 'Nouveau motif'}, token: patient);
      expect(status, 409);
      expect(body['error'], contains('en attente'));
    });

    test('un autre patient ne peut pas modifier', () async {
      final id = await createRequest();
      final (status, _) = await server.call('PATCH', '/teledoc/requests/$id',
          body: {'motif': 'Piratage'}, token: otherPatient);
      expect(status, 404);
    });
  });

  group('Annuler une demande', () {
    test('patient, en attente : annulée et remboursée', () async {
      final id = await createRequest();
      final (status, body) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: patient);
      expect(status, 200);
      expect(body['statut'], 'annulee');
      expect(server.payments.refunds, [1000 + id]);

      final (again, _) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: patient);
      expect(again, 409);
      expect(server.payments.refunds, hasLength(1), reason: 'pas de double');
      // Annulée → le patient peut refaire une demande.
      await createRequest();
    });

    test('remboursement refusé : la demande reste en attente', () async {
      final id = await createRequest();
      server.payments.declineRefunds = true;
      final (status, body) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: patient);
      expect(status, 409);
      expect(body['error'], contains('Remboursement impossible'));
      final (_, after) =
          await server.call('GET', '/teledoc/requests/$id', token: patient);
      expect(after['statut'], 'en_attente');
    });

    test(
        'consultation commencée : le patient ne peut plus annuler, '
        'le médecin en charge oui', () async {
      final id = await createRequest();
      final consultation = await startConsultation(id);

      final (byPatient, body) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: patient);
      expect(byPatient, 409);
      expect(body['error'], contains('seul le médecin'));

      final (byOther, _) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: otherDoctor);
      expect(byOther, 404);

      final (byDoctor, cancelled) = await server
          .call('POST', '/teledoc/requests/$id/cancel', token: doctor);
      expect((byDoctor, cancelled['statut']), (200, 'annulee'));
      final (_, c) = await server
          .call('GET', '/teledoc/consultations/$consultation', token: doctor);
      expect(c['date_fin'], isNotNull, reason: 'médecin libéré');
      expect(server.payments.refunds, [1000 + id]);
    });
  });

  group('Consultations', () {
    test('terminer : ordonnance obligatoire, demande terminée', () async {
      final id = await createRequest();
      final c = await startConsultation(id);

      final (missing, err) = await server.call(
          'POST', '/teledoc/consultations/$c/end',
          body: <String, dynamic>{}, token: doctor);
      expect((missing, err['error']), (400, 'Ordonnance obligatoire'));

      final (status, body) = await server.call(
          'POST', '/teledoc/consultations/$c/end',
          body: {'ordonnance': 'Paracétamol 1 g, 3 fois par jour'},
          token: doctor);
      expect(status, 200);
      expect(body['date_fin'], isNotNull);
      expect(body['statut_demande'], 'terminee');

      final (again, _) = await server.call(
          'POST', '/teledoc/consultations/$c/end',
          body: {'ordonnance': 'Encore'}, token: doctor);
      expect(again, 409);
    });

    test('historique : chacun voit les siennes', () async {
      final id = await createRequest();
      final c = await startConsultation(id);

      final (_, forPatient) =
          await server.call('GET', '/teledoc/consultations', token: patient);
      expect((forPatient['items'] as List).single['id'], c);
      final (_, forDoctor) =
          await server.call('GET', '/teledoc/consultations', token: doctor);
      expect((forDoctor['items'] as List).single['patient_nom'],
          'Ameni Utilisateur');
      final (_, forOtherDoctor) = await server
          .call('GET', '/teledoc/consultations', token: otherDoctor);
      expect(forOtherDoctor['items'], isEmpty);
      final (_, forOtherPatient) = await server
          .call('GET', '/teledoc/consultations', token: otherPatient);
      expect(forOtherPatient['items'], isEmpty);
      final (hidden, _) = await server.call('GET', '/teledoc/consultations/$c',
          token: otherPatient);
      expect(hidden, 404);
    });

    test('modifier : ordonnance corrigeable après la fin, type non', () async {
      final id = await createRequest();
      final c = await startConsultation(id);

      final (typeOk, t) = await server.call(
          'PATCH', '/teledoc/consultations/$c',
          body: {'type': 'audio'}, token: doctor);
      expect((typeOk, t['type']), (200, 'audio'));

      await server.call('POST', '/teledoc/consultations/$c/end',
          body: {'ordonnance': 'Repos 48 h'}, token: doctor);

      final (fixed, f) = await server.call('PATCH', '/teledoc/consultations/$c',
          body: {'ordonnance': 'Repos 72 h'}, token: doctor);
      expect((fixed, f['ordonnance']), (200, 'Repos 72 h'));

      final (typeLate, _) = await server.call(
          'PATCH', '/teledoc/consultations/$c',
          body: {'type': 'video'}, token: doctor);
      expect(typeLate, 409);

      final (byPatient, _) = await server.call(
          'PATCH', '/teledoc/consultations/$c',
          body: {'ordonnance': 'Auto-prescription'}, token: patient);
      expect(byPatient, 403);
    });

    test('supprimer : en cours → remise en file ; terminée → refusé', () async {
      final id = await createRequest();
      final c = await startConsultation(id);
      final (deleted, _) = await server
          .call('DELETE', '/teledoc/consultations/$c', token: doctor);
      expect(deleted, 204);
      final (_, request) =
          await server.call('GET', '/teledoc/requests/$id', token: patient);
      expect(request['statut'], 'en_attente');
      expect(request['consultation_id'], isNull);

      final c2 = await startConsultation(id);
      await server.call('POST', '/teledoc/consultations/$c2/end',
          body: {'ordonnance': 'Repos'}, token: doctor);
      final (refused, body) = await server
          .call('DELETE', '/teledoc/consultations/$c2', token: doctor);
      expect(refused, 409);
      expect(body['error'], contains('dossier médical'));
    });

    test('pharmacie : choisie par le patient après la consultation', () async {
      await server.insertPharmacies();
      final id = await createRequest();
      final c = await startConsultation(id);

      final (early, _) = await server.call(
          'PATCH', '/teledoc/consultations/$c/pharmacy',
          body: {'id_pharmacie': 1}, token: patient);
      expect(early, 409);

      await server.call('POST', '/teledoc/consultations/$c/end',
          body: {'ordonnance': 'Repos'}, token: doctor);
      final (unknown, _) = await server.call(
          'PATCH', '/teledoc/consultations/$c/pharmacy',
          body: {'id_pharmacie': 999}, token: patient);
      expect(unknown, 404);
      final (status, body) = await server.call(
          'PATCH', '/teledoc/consultations/$c/pharmacy',
          body: {'id_pharmacie': 2}, token: patient);
      expect(status, 200);
      expect(body['pharmacie_nom'], 'Pharmacie des Berges du Lac');
    });
  });

  group('Pharmacies de garde', () {
    test('triées par distance, pharmacies fermées exclues', () async {
      await server.insertPharmacies();
      // Depuis La Marsa.
      final (status, body) = await server.call(
          'GET', '/teledoc/pharmacies/on-duty?lat=36.8790&lng=10.3240&limit=50',
          token: patient);
      expect(status, 200);
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(7));
      expect(items.first['nom'], 'Pharmacie de La Marsa');
      expect(items.first['distance_km'], lessThan(1));
      final distances = items.map((i) => i['distance_km'] as num).toList();
      expect(distances, orderedEquals([...distances]..sort()));
      expect(items.any((i) => i['nom'] == 'Pharmacie Bab Saadoun'), isFalse);
    });

    test('limit et coordonnées validés', () async {
      await server.insertPharmacies();
      final (_, two) = await server.call(
          'GET', '/teledoc/pharmacies/on-duty?lat=36.8&lng=10.18&limit=2',
          token: doctor);
      expect(two['items'], hasLength(2));
      final (missing, _) = await server
          .call('GET', '/teledoc/pharmacies/on-duty?lat=36.8', token: patient);
      expect(missing, 400);
      final (outOfRange, body) = await server.call(
          'GET', '/teledoc/pharmacies/on-duty?lat=95&lng=10',
          token: patient);
      expect((outOfRange, body['error']), (400, 'Coordonnées GPS invalides'));
    });
  });
}
