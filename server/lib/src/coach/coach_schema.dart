import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// CoachProche tables (schema version 8). Every statement is idempotent
/// (`IF NOT EXISTS`): the function runs on a fresh database *and* when an
/// older database is upgraded.
///
/// All timestamps are UTC ISO-8601 strings ("...Z"), so lexical comparison
/// is chronological. Money: whole cents (`INTEGER`).
Future<void> createCoachSchema(DatabaseExecutor db) async {
  // A sport session published by a coach.
  // places_restantes is decremented atomically on booking and given back on
  // cancellation (never read-then-write).
  await db.execute('''
CREATE TABLE IF NOT EXISTS coach_seance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  titre TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  lieu TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  date_heure TEXT NOT NULL,
  duree_minutes INTEGER NOT NULL CHECK (duree_minutes > 0),
  niveau TEXT NOT NULL,
  places_totales INTEGER NOT NULL CHECK (places_totales > 0),
  places_restantes INTEGER NOT NULL CHECK (places_restantes >= 0),
  prix_centimes INTEGER NOT NULL CHECK (prix_centimes >= 0),
  statut TEXT NOT NULL DEFAULT 'planifiee',
  coach_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL,
  mis_a_jour_le TEXT NOT NULL,
  CHECK (places_restantes <= places_totales)
)
''');

  // statut: en_attente | confirmee | annulee | present.
  // statut_paiement: TransactionStatus apiValue of the linked transaction_
  // (NULL for a free session).
  // code_qr_nonce: secret part of the current QR; NULL = no usable QR
  // (cancelled / already present).
  await db.execute('''
CREATE TABLE IF NOT EXISTS coach_reservation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  seance_id INTEGER NOT NULL REFERENCES coach_seance(id) ON DELETE CASCADE,
  client_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  statut TEXT NOT NULL DEFAULT 'en_attente',
  code_qr_nonce TEXT,
  montant_centimes INTEGER NOT NULL,
  mode_paiement TEXT,
  moyen_paiement_id INTEGER REFERENCES moyen_paiement(id) ON DELETE SET NULL,
  statut_paiement TEXT,
  transaction_id INTEGER REFERENCES transaction_(id) ON DELETE SET NULL,
  pas INTEGER,
  distance_km REAL,
  frequence_cardiaque INTEGER,
  present_le TEXT,
  annule_le TEXT,
  annule_par TEXT,
  cree_le TEXT NOT NULL
)
''');

  // One active booking per client and session.
  await db.execute('''
CREATE UNIQUE INDEX IF NOT EXISTS coach_reservation_active_unique
ON coach_reservation(seance_id, client_id) WHERE statut <> 'annulee'
''');
  await db.execute('CREATE INDEX IF NOT EXISTS coach_reservation_client_idx '
      'ON coach_reservation(client_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS coach_reservation_seance_idx '
      'ON coach_reservation(seance_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS coach_seance_date_idx '
      'ON coach_seance(date_heure)');
  await db.execute('CREATE INDEX IF NOT EXISTS coach_seance_coach_idx '
      'ON coach_seance(coach_id)');

  // cle_evenement makes every notification idempotent (the same event never
  // produces two notifications), e.g. 'rappel:12:2026-11-08T09:00:00.000Z'.
  await db.execute('''
CREATE TABLE IF NOT EXISTS coach_notification (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  titre TEXT NOT NULL,
  message TEXT NOT NULL,
  seance_id INTEGER REFERENCES coach_seance(id) ON DELETE CASCADE,
  reservation_id INTEGER REFERENCES coach_reservation(id) ON DELETE CASCADE,
  cle_evenement TEXT NOT NULL UNIQUE,
  lu INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');
  await db.execute('CREATE INDEX IF NOT EXISTS coach_notification_user_idx '
      'ON coach_notification(utilisateur_id, lu)');

  // Server-side key/value settings (the QR HMAC secret).
  await db.execute('''
CREATE TABLE IF NOT EXISTS coach_parametre (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL
)
''');
}
