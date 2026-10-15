import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// FoodSave tables (schema version 2). All timestamps are UTC ISO-8601
/// strings ("...Z") so lexical comparison == chronological comparison.
/// Money: whole cents (`INTEGER`).
Future<void> createFoodSaveSchema(DatabaseExecutor db) async {
  // One store per merchant, with the GPS position used for the 5 km radius.
  await db.execute('''
CREATE TABLE commerce (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  commercant_id INTEGER NOT NULL UNIQUE REFERENCES utilisateur(id) ON DELETE CASCADE,
  nom TEXT NOT NULL,
  adresse TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  categorie TEXT NOT NULL,
  cree_le TEXT NOT NULL,
  mis_a_jour_le TEXT NOT NULL
)
''');

  // Last known client position (opt-in; row deleted when the client refuses).
  await db.execute('''
CREATE TABLE localisation_client (
  utilisateur_id INTEGER PRIMARY KEY REFERENCES utilisateur(id) ON DELETE CASCADE,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  mis_a_jour_le TEXT NOT NULL
)
''');

  // quantite = units still on sale (decremented atomically on reservation,
  // restored on expiry/cancel). quantite_initiale = units ever put on sale.
  await db.execute('''
CREATE TABLE panier (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  titre TEXT NOT NULL,
  contenu TEXT NOT NULL,
  categorie TEXT NOT NULL,
  image TEXT,
  prix_centimes INTEGER NOT NULL CHECK (prix_centimes > 0),
  prix_initial_centimes INTEGER NOT NULL,
  quantite INTEGER NOT NULL CHECK (quantite >= 0),
  quantite_initiale INTEGER NOT NULL CHECK (quantite_initiale >= 0),
  creneau_retrait_debut TEXT NOT NULL,
  creneau_retrait_fin TEXT NOT NULL,
  date_expiration TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'disponible',
  commercant_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL,
  mis_a_jour_le TEXT NOT NULL,
  CHECK (prix_initial_centimes > prix_centimes)
)
''');

  // statut: en_attente | retire | expire | annule (pickup lifecycle).
  // statut_paiement: TransactionStatus apiValue of the linked transaction_.
  // qr_nonce: current QR secret part; NULL = no usable QR (unpaid / used /
  // expired / cancelled). quantite_liberee guards against double release.
  await db.execute('''
CREATE TABLE reservation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente',
  panier_id INTEGER NOT NULL REFERENCES panier(id) ON DELETE CASCADE,
  client_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  quantite_reservee INTEGER NOT NULL CHECK (quantite_reservee >= 1),
  montant_centimes INTEGER NOT NULL,
  mode_paiement TEXT,
  moyen_paiement_id INTEGER REFERENCES moyen_paiement(id) ON DELETE SET NULL,
  statut_paiement TEXT NOT NULL DEFAULT 'en_attente',
  transaction_id INTEGER REFERENCES transaction_(id) ON DELETE SET NULL,
  qr_nonce TEXT,
  date_creation_qr TEXT,
  date_expiration_qr TEXT,
  retire_le TEXT,
  quantite_liberee INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');

  // cle_evenement makes every notification idempotent (no duplicates for
  // the same event), e.g. 'nouveau_panier:12:user:4'.
  await db.execute('''
CREATE TABLE foodsave_notification (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  titre TEXT NOT NULL,
  message TEXT NOT NULL,
  panier_id INTEGER REFERENCES panier(id) ON DELETE CASCADE,
  reservation_id INTEGER REFERENCES reservation(id) ON DELETE CASCADE,
  cle_evenement TEXT NOT NULL UNIQUE,
  lu INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
)
''');

  // Audit log of important events (création, QR, scan, expiration, ...).
  await db.execute('''
CREATE TABLE foodsave_journal (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evenement TEXT NOT NULL,
  utilisateur_id INTEGER,
  panier_id INTEGER,
  reservation_id INTEGER,
  details TEXT,
  cree_le TEXT NOT NULL
)
''');

  // Server-side key/value settings (e.g. the QR HMAC secret).
  await db.execute('''
CREATE TABLE foodsave_parametre (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL
)
''');

  await db.execute(
      'CREATE INDEX panier_commercant_idx ON panier(commercant_id)');
  await db.execute('CREATE INDEX panier_statut_idx ON panier(statut)');
  await db.execute(
      'CREATE INDEX reservation_panier_idx ON reservation(panier_id)');
  await db.execute(
      'CREATE INDEX reservation_client_idx ON reservation(client_id)');
  await db.execute(
      'CREATE INDEX reservation_actives_idx ON reservation(statut, date_expiration_qr)');
  await db.execute(
      'CREATE INDEX notification_user_idx ON foodsave_notification(utilisateur_id, lu)');
}
