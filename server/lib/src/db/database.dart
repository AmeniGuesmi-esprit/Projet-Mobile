import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../foodsave/foodsave_schema.dart';

/// Opens (and migrates) the ProxiLife SQLite database.
///
/// Schema versions:
///  - v1 : utilisateur, code_verification, session, moyen_paiement, transaction_
///  - v2 : FoodSave
///  - v3 : FoodSave, durée de réservation des paniers
///  - v4 : covoiturage (vehicule, trajet) + utilisateur.sexe
///  - v5 : reservation (demandes de places sur un trajet)
///  - v6 : embarquement (QR code / Bluetooth) sur reservation + secret par trajet
///
/// An existing v1 file is upgraded in place (no data is lost).
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  Database get db => _db;



  static Future<AppDatabase> open(String path) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final absolute = p.isAbsolute(path) ? path : p.join(Directory.current.path, path);
    final db = await databaseFactory.openDatabase(absolute, options: _options());
    return AppDatabase._(db);
  }

  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: _options(),
    );
    return AppDatabase._(db);
  }

  /// v1: users + payments. v2: FoodSave (see foodsave_schema.dart).
  /// v3: per-basket reservation duration (`panier.duree_reservation_minutes`).
  /// v4: covoiturage (vehicule, trajet, utilisateur.sexe).
  /// v5: reservation (demandes de places).
  /// v6: embarquement (QR code / Bluetooth).
  static const int schemaVersion = 6;

  static OpenDatabaseOptions _options() => OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _enableForeignKeys,
        onCreate: (db, version) async {
          // _createSchemaV1 crée aussi les tables FoodSave (dernière version).
          await _createSchemaV1(db);
          await _migrateToV2(db); // covoiturage  (v4 de la base)
          await _migrateToV3(db); // réservations (v5 de la base)
          await _migrateToV4(db); // embarquement (v6 de la base)
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // FoodSave (ton ami)
          if (oldVersion < 2) {
            // Crée directement les tables FoodSave à jour.
            await createFoodSaveSchema(db);
          } else if (oldVersion < 3) {
            await db.execute('ALTER TABLE panier ADD COLUMN '
                'duree_reservation_minutes INTEGER NOT NULL DEFAULT 30');
          }
          // Covoiturage (toi)
          if (oldVersion < 4) await _migrateToV2(db);
          if (oldVersion < 5) await _migrateToV3(db);
          if (oldVersion < 6) await _migrateToV4(db);
        },
      );

  static Future<void> _enableForeignKeys(DatabaseExecutor db) async =>
      db.execute('PRAGMA foreign_keys = ON');

  // ---------------------------------------------------------------- v1 ----

  static Future<void> _createSchemaV1(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE utilisateur (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL,
  prenom TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  telephone TEXT NOT NULL,
  mot_de_passe_hash TEXT NOT NULL,
  photo TEXT,
  role TEXT NOT NULL,
  statut_compte TEXT NOT NULL DEFAULT 'en_attente_verification',
  rib TEXT,
  solde_centimes INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE code_verification (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code_hash TEXT NOT NULL,
  methode TEXT NOT NULL DEFAULT 'email',
  date_expiration TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente',
  tentatives INTEGER NOT NULL DEFAULT 0,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE session (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash TEXT NOT NULL UNIQUE,
  date_expiration TEXT NOT NULL,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE moyen_paiement (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  quatre_derniers_chiffres TEXT,
  nom_titulaire TEXT,
  date_expiration TEXT,
  par_defaut INTEGER NOT NULL DEFAULT 0,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE transaction_ (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  montant_centimes INTEGER NOT NULL,
  devise TEXT NOT NULL DEFAULT 'TND',
  date TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente',
  type_service TEXT NOT NULL,
  id_reference TEXT,
  facture_numero TEXT NOT NULL UNIQUE,
  utilisateur_id INTEGER REFERENCES utilisateur(id),
  beneficiaire_id INTEGER REFERENCES utilisateur(id),
  moyen_paiement_id INTEGER REFERENCES moyen_paiement(id) ON DELETE SET NULL
)
''');

    await db.execute(
      'CREATE UNIQUE INDEX utilisateur_email_unique ON utilisateur(email)',
    );
    await db.execute(
      'CREATE INDEX transaction_utilisateur_idx ON transaction_(utilisateur_id)',
    );
    await db.execute(
      'CREATE INDEX transaction_beneficiaire_idx ON transaction_(beneficiaire_id)',
    );
    await createFoodSaveSchema(db);
  }

  // ---------------------------------------------------------------- v2 ----

  /// Carpooling: vehicles and trips. Préférences de voyage and the departure /
  /// arrival places are stored as columns of `trajet` (one row = one trip).
  static Future<void> _migrateToV2(DatabaseExecutor db) async {
    // Sexe déclaré (facultatif) : sert uniquement à l'option « réservé aux femmes ».
    await db.execute('ALTER TABLE utilisateur ADD COLUMN sexe TEXT');

    await db.execute('''
CREATE TABLE vehicule (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  marque TEXT NOT NULL,
  modele TEXT NOT NULL,
  couleur TEXT NOT NULL,
  nb_places INTEGER NOT NULL,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE trajet (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conducteur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  vehicule_id INTEGER NOT NULL REFERENCES vehicule(id),
  depart_adresse TEXT NOT NULL,
  depart_latitude REAL NOT NULL,
  depart_longitude REAL NOT NULL,
  arrivee_adresse TEXT NOT NULL,
  arrivee_latitude REAL NOT NULL,
  arrivee_longitude REAL NOT NULL,
  date_heure_depart TEXT NOT NULL,
  places_disponibles INTEGER NOT NULL,
  places_totales INTEGER NOT NULL,
  prix_par_place_centimes INTEGER NOT NULL,
  devise TEXT NOT NULL DEFAULT 'TND',
  statut TEXT NOT NULL DEFAULT 'ouvert',
  motif_annulation TEXT,
  ambiance TEXT NOT NULL DEFAULT 'indifferent',
  fumeur_accepte INTEGER NOT NULL DEFAULT 0,
  animaux_acceptes INTEGER NOT NULL DEFAULT 0,
  reserve_aux_femmes INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX vehicule_utilisateur_idx ON vehicule(utilisateur_id)',
    );
    await db.execute(
      'CREATE INDEX trajet_conducteur_idx ON trajet(conducteur_id)',
    );
    await db.execute(
      'CREATE INDEX trajet_date_idx ON trajet(date_heure_depart)',
    );
    await db.execute(
      'CREATE INDEX trajet_depart_geo_idx ON trajet(depart_latitude, depart_longitude)',
    );
  }

  // ---------------------------------------------------------------- v3 ----

  /// Reservations: a passenger asks for [nb_places] seats on a trip; the driver
  /// accepts or refuses; the passenger may cancel. Seats are only taken from
  /// `trajet.places_disponibles` when the driver accepts.
  static Future<void> _migrateToV3(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE reservation_trajet (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trajet_id INTEGER NOT NULL REFERENCES trajet(id) ON DELETE CASCADE,
  passager_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  nb_places INTEGER NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente',
  date_reservation TEXT NOT NULL,
  date_decision TEXT
)
''');
    await db.execute(
      'CREATE INDEX reservation_trajet_trajet_idx ON reservation_trajet(trajet_id)',
    );
    await db.execute(
      'CREATE INDEX reservation_trajet_passager_idx ON reservation_trajet(passager_id)',
    );
  }

  // ---------------------------------------------------------------- v4 ----

  /// Boarding check: the driver's app shows a short-lived code (QR or sent over
  /// Bluetooth) derived from a per-trip secret; the passenger confirms boarding
  /// with it. The secret never leaves the server.
  static Future<void> _migrateToV4(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE trajet ADD COLUMN code_embarquement_secret TEXT',
    );
    await db.execute('ALTER TABLE reservation_trajet ADD COLUMN embarque_le TEXT');
    await db.execute('ALTER TABLE reservation_trajet ADD COLUMN embarque_methode TEXT');
    await db.execute('ALTER TABLE reservation_trajet ADD COLUMN embarque_latitude REAL');
    await db.execute('ALTER TABLE reservation_trajet ADD COLUMN embarque_longitude REAL');
    await db.execute(
      'ALTER TABLE reservation_trajet ADD COLUMN embarque_tentatives INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> close() async {
    await _db.close();
  }
}
