import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates the ServiceNow tables. Every statement is idempotent, so the same
/// function serves fresh databases and upgrades.
///
/// - `intervention.prestataire_id` is set to null on account deletion, so
///   that deleting an account is never blocked.
/// - `transaction_id` has no foreign key: payments belong to the Payment
///   module, like in TeleDoc.
Future<void> createServiceNowSchema(DatabaseExecutor db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS demande_service (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  description TEXT NOT NULL,
  adresse TEXT NOT NULL,
  date_souhaitee TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente'
    CHECK (statut IN ('en_attente', 'acceptee', 'en_cours', 'terminee', 'annulee')),
  cree_le TEXT NOT NULL,
  modifie_le TEXT NOT NULL
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS intervention (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  demande_id INTEGER NOT NULL REFERENCES demande_service(id) ON DELETE CASCADE,
  prestataire_id INTEGER REFERENCES utilisateur(id) ON DELETE SET NULL,
  date_prevue TEXT NOT NULL,
  date_debut TEXT,
  date_fin TEXT,
  rapport TEXT,
  prix_centimes INTEGER NOT NULL CHECK (prix_centimes >= 0),
  statut TEXT NOT NULL DEFAULT 'planifiee'
    CHECK (statut IN ('planifiee', 'en_cours', 'terminee', 'annulee')),
  transaction_id INTEGER,
  cree_le TEXT NOT NULL,
  modifie_le TEXT NOT NULL
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS prestataire_profil (
  utilisateur_id INTEGER PRIMARY KEY REFERENCES utilisateur(id) ON DELETE CASCADE,
  specialites TEXT NOT NULL DEFAULT '',
  latitude REAL,
  longitude REAL,
  modifie_le TEXT NOT NULL
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS service_now_notification (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  demande_id INTEGER NOT NULL REFERENCES demande_service(id) ON DELETE CASCADE,
  titre TEXT NOT NULL,
  message TEXT NOT NULL,
  livree INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS service_now_notification_idx '
    'ON service_now_notification(utilisateur_id, livree)',
  );

  await db.execute('''
CREATE TABLE IF NOT EXISTS prestataire_creneau (
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  jour INTEGER NOT NULL CHECK (jour BETWEEN 1 AND 7),
  debut_minutes INTEGER NOT NULL,
  fin_minutes INTEGER NOT NULL,
  PRIMARY KEY (utilisateur_id, jour)
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS prestataire_jour_off (
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  jour TEXT NOT NULL,
  PRIMARY KEY (utilisateur_id, jour)
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS service_now_message (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  demande_id INTEGER NOT NULL REFERENCES demande_service(id) ON DELETE CASCADE,
  auteur_id INTEGER REFERENCES utilisateur(id) ON DELETE SET NULL,
  contenu TEXT NOT NULL,
  cree_le TEXT NOT NULL
)
''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS service_now_message_idx '
    'ON service_now_message(demande_id, id)',
  );

  await _addMissingColumns(db, 'demande_service', const {
    'latitude': 'REAL',
    'longitude': 'REAL',
  });
  await _addMissingColumns(db, 'intervention', const {
    'qr_code': 'TEXT',
    'en_route_le': 'TEXT',
    'prestataire_lat': 'REAL',
    'prestataire_lng': 'REAL',
    'position_le': 'TEXT',
    'photo_avant': 'TEXT',
    'photo_apres': 'TEXT',
    'note': 'INTEGER CHECK (note BETWEEN 1 AND 5)',
    'commentaire': 'TEXT',
  });

  await db.execute(
    'CREATE INDEX IF NOT EXISTS demande_service_client_idx '
    'ON demande_service(client_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS demande_service_statut_idx '
    'ON demande_service(statut, date_souhaitee)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS intervention_prestataire_idx '
    'ON intervention(prestataire_id)',
  );
  // A request has at most one live intervention, enforced by SQLite itself.
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS intervention_une_active '
    "ON intervention(demande_id) WHERE statut <> 'annulee'",
  );
}

/// SQLite has no `ADD COLUMN IF NOT EXISTS`: checks the table first, so an
/// existing database gains the new columns and keeps its data.
Future<void> _addMissingColumns(
  DatabaseExecutor db,
  String table,
  Map<String, String> columns,
) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  final existing = {for (final row in rows) row['name'] as String};
  for (final column in columns.entries) {
    if (!existing.contains(column.key)) {
      await db.execute(
          'ALTER TABLE $table ADD COLUMN ${column.key} ${column.value}');
    }
  }
}
