import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens (and migrates) the ProxiLife SQLite database.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  Database get db => _db;

  static Future<AppDatabase> open(String path) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final absolute = p.isAbsolute(path) ? path : p.join(Directory.current.path, path);
    final db = await databaseFactory.openDatabase(
      absolute,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _enableForeignKeys,
        onCreate: (db, version) async => _createSchema(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _enableForeignKeys,
        onCreate: (db, version) async => _createSchema(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _enableForeignKeys(DatabaseExecutor db) async =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> _createSchema(DatabaseExecutor db) async {
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
  }

  Future<void> close() async {
    await _db.close();
  }
}
