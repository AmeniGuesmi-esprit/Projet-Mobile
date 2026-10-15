import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database version required by the current TeleDoc schema
/// (v2 : TeleDoc tables, v3 : `salle_appel`).
const int teledocSchemaVersion = 3;

/// Creates the TeleDoc Express tables and indexes (see
/// `docs/teledoc/CONCEPTION.md` §2). Called by `AppDatabase` on a fresh
/// database (`onCreate`) and, through [upgradeTeledocSchema], on upgrades.
/// Every statement is idempotent (`IF NOT EXISTS`).
///
/// - `position_file` / `temps_estime` are not stored: they are derived from
///   the queue on every read (decision D2).
/// - `transaction_id` has no foreign key: the Payment module is owned by
///   another team member and only reached through `TeledocPaymentGateway`
///   (decision D11).
/// - References to `utilisateur` cascade / set null so that account deletion
///   (a real DELETE in the User module) is never blocked (decision D8).
Future<void> createTeledocSchema(DatabaseExecutor db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS teledoc_pharmacie (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL,
  adresse TEXT NOT NULL,
  telephone TEXT NOT NULL,
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  de_garde INTEGER NOT NULL DEFAULT 0 CHECK (de_garde IN (0, 1))
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS teledoc_demande (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  motif TEXT NOT NULL,
  description TEXT NOT NULL,
  urgence TEXT NOT NULL CHECK (urgence IN ('faible', 'moyenne', 'elevee')),
  photo_symptome TEXT,
  statut TEXT NOT NULL DEFAULT 'en_attente'
    CHECK (statut IN ('en_attente', 'en_cours', 'terminee', 'annulee')),
  patient_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  transaction_id INTEGER,
  cree_le TEXT NOT NULL,
  modifie_le TEXT NOT NULL
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS teledoc_consultation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date_debut TEXT NOT NULL,
  date_fin TEXT,
  type TEXT NOT NULL CHECK (type IN ('audio', 'video')),
  ordonnance TEXT,
  pharmacie_id INTEGER REFERENCES teledoc_pharmacie(id) ON DELETE SET NULL,
  demande_id INTEGER NOT NULL UNIQUE
    REFERENCES teledoc_demande(id) ON DELETE CASCADE,
  medecin_id INTEGER REFERENCES utilisateur(id) ON DELETE SET NULL,
  salle_appel TEXT
)
''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS teledoc_demande_file_idx ON teledoc_demande(statut, cree_le)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS teledoc_demande_patient_idx ON teledoc_demande(patient_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS teledoc_consultation_medecin_idx '
    'ON teledoc_consultation(medecin_id)',
  );
  // At most one open consultation per doctor, enforced by SQLite itself.
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS teledoc_consultation_une_en_cours '
    'ON teledoc_consultation(medecin_id) WHERE date_fin IS NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS teledoc_pharmacie_garde_idx ON teledoc_pharmacie(de_garde)',
  );
}

/// `onUpgrade` hook. Brings any older database to the current TeleDoc
/// schema without depending on the exact version number: tables are created
/// if missing, columns added if missing. The order in which modules are
/// merged (and the final version number) therefore does not matter (D36).
Future<void> upgradeTeledocSchema(
  DatabaseExecutor db,
  int oldVersion,
  int newVersion,
) async {
  await createTeledocSchema(db);
  final columns = await db.rawQuery('PRAGMA table_info(teledoc_consultation)');
  if (!columns.any((c) => c['name'] == 'salle_appel')) {
    await db.execute(
        'ALTER TABLE teledoc_consultation ADD COLUMN salle_appel TEXT');
    // Consultations still open at upgrade time get a room immediately.
    await db.execute(
      "UPDATE teledoc_consultation SET salle_appel = 'ProxiLifeTeleDoc' || "
      'lower(hex(randomblob(16))) WHERE date_fin IS NULL',
    );
  }
}
