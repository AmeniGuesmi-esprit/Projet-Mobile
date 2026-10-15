import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/db/teledoc_schema.dart';
import 'package:proxilife_server/src/db/teledoc_seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'teledoc_test_support.dart';

void main() {
  group('Schéma TeleDoc', () {
    late AppDatabase database;
    late Database db;

    setUp(() async {
      database = await AppDatabase.inMemory();
      db = database.db;
    });
    tearDown(() => database.close());

    test('une base neuve contient les 3 tables et l\'index partiel', () async {
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE 'teledoc_%'");
      final names = rows.map((r) => r['name']).toSet();
      expect(
          names,
          containsAll([
            'teledoc_pharmacie',
            'teledoc_demande',
            'teledoc_consultation',
            'teledoc_consultation_une_en_cours',
          ]));
      expect(await db.getVersion(), 3);
    });

    test('les CHECK refusent une urgence inconnue', () async {
      final patient = await insertTestUser(db, 'p@test.tn', 'client');
      expect(
        () => db.insert('teledoc_demande', {
          'motif': 'Test',
          'description': 'Description de test',
          'urgence': 'critique',
          'patient_id': patient,
          'cree_le': '2026-10-14T09:00:00',
          'modifie_le': '2026-10-14T09:00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('un médecin ne peut pas avoir deux consultations ouvertes', () async {
      final patient = await insertTestUser(db, 'p@test.tn', 'client');
      final doctor = await insertTestUser(db, 'd@test.tn', 'medecin');
      final d1 = await insertTestRequest(db, patient);
      final d2 = await insertTestRequest(db, patient);
      Future<int> open(int demande) => db.insert('teledoc_consultation', {
            'date_debut': '2026-10-14T09:00:00',
            'type': 'audio',
            'demande_id': demande,
            'medecin_id': doctor,
          });
      await open(d1);
      expect(() => open(d2), throwsA(isA<DatabaseException>()));
    });

    test('supprimer un compte patient supprime ses demandes (pas de blocage)',
        () async {
      final patient = await insertTestUser(db, 'p@test.tn', 'client');
      final doctor = await insertTestUser(db, 'd@test.tn', 'medecin');
      final demande = await insertTestRequest(db, patient);
      await db.insert('teledoc_consultation', {
        'date_debut': '2026-10-14T09:00:00',
        'type': 'video',
        'demande_id': demande,
        'medecin_id': doctor,
      });

      await db.delete('utilisateur', where: 'id = ?', whereArgs: [doctor]);
      final consultation = await db.query('teledoc_consultation');
      expect(consultation.single['medecin_id'], isNull);

      await db.delete('utilisateur', where: 'id = ?', whereArgs: [patient]);
      expect(await db.query('teledoc_demande'), isEmpty);
      expect(await db.query('teledoc_consultation'), isEmpty);
    });
  });

  test('migration v1 → v2 : ajoute les tables sans toucher aux données',
      () async {
    final dir = await Directory.systemTemp.createTemp('teledoc_migration');
    final path = p.join(dir.path, 'v1.db');
    sqfliteFfiInit();
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
                'CREATE TABLE utilisateur (id INTEGER PRIMARY KEY, nom TEXT)');
            await db.insert('utilisateur', {'nom': 'Ancien'});
          },
        ));
    await v1.close();

    final upgraded = await AppDatabase.open(path);
    expect(await upgraded.db.getVersion(), 3);
    expect((await upgraded.db.query('utilisateur')).single['nom'], 'Ancien');
    expect(await upgraded.db.query('teledoc_pharmacie'), isEmpty);
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('migration v2 → v3 : ajoute salle_appel, idempotente', () async {
    final dir = await Directory.systemTemp.createTemp('teledoc_migration');
    final path = p.join(dir.path, 'v2.db');
    sqfliteFfiInit();
    // A v2 database as it existed before Étape 9 (no salle_appel column).
    final v2 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
                'CREATE TABLE utilisateur (id INTEGER PRIMARY KEY, nom TEXT)');
            await db.insert('utilisateur', {'id': 1, 'nom': 'Patient'});
            await db.insert('utilisateur', {'id': 2, 'nom': 'Médecin'});
            await db.execute('''
CREATE TABLE teledoc_demande (id INTEGER PRIMARY KEY, motif TEXT,
  description TEXT, urgence TEXT, photo_symptome TEXT, statut TEXT,
  patient_id INTEGER, transaction_id INTEGER, cree_le TEXT, modifie_le TEXT)''');
            await db.execute('''
CREATE TABLE teledoc_consultation (id INTEGER PRIMARY KEY, date_debut TEXT,
  date_fin TEXT, type TEXT, ordonnance TEXT, pharmacie_id INTEGER,
  demande_id INTEGER, medecin_id INTEGER)''');
            for (final (id, fin) in [(1, null), (2, '2026-10-14T10:00:00')]) {
              await db.insert('teledoc_demande', {'id': id, 'patient_id': 1});
              await db.insert('teledoc_consultation', {
                'id': id,
                'date_debut': '2026-10-14T09:00:00',
                'date_fin': fin,
                'type': 'audio',
                'demande_id': id,
                'medecin_id': 2,
              });
            }
          },
        ));
    await v2.close();

    final upgraded = await AppDatabase.open(path);
    expect(await upgraded.db.getVersion(), 3);
    final rows = await upgraded.db
        .query('teledoc_consultation', orderBy: 'id', columns: ['salle_appel']);
    // The open consultation gets a room, the finished one does not need one.
    expect(rows[0]['salle_appel'], matches(r'^ProxiLifeTeleDoc[0-9a-f]{32}$'));
    expect(rows[1]['salle_appel'], isNull);
    // Running the hook again changes nothing (merge-order independent).
    await upgradeTeledocSchema(upgraded.db, 2, 3);
    expect(
        (await upgraded.db.query('teledoc_consultation', orderBy: 'id'))
            .first['salle_appel'],
        rows[0]['salle_appel']);
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('seed TeleDoc : médecins, pharmacies, démo, idempotent', () async {
    final database = await AppDatabase.inMemory();
    final db = database.db;
    await insertTestUser(db, 'client@proxilife.fr', 'client');
    await insertTestUser(db, 'fawzi.saidi@esprit.tn', 'client');

    await seedTeledoc(db);
    await seedTeledoc(db); // second run must not duplicate anything

    final doctors = await db.query('utilisateur', where: "role = 'medecin'");
    expect(doctors, hasLength(3));
    for (final doctor in doctors) {
      expect(doctor['statut_compte'], 'actif');
      expect(doctor['rib'], hasLength(23));
    }
    expect(await db.query('teledoc_pharmacie'), hasLength(8));
    expect(await db.query('teledoc_pharmacie', where: 'de_garde = 1'),
        hasLength(7));
    expect(await db.query('teledoc_demande'), hasLength(2));
    expect(await db.query('teledoc_consultation'), hasLength(1));
    await database.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
