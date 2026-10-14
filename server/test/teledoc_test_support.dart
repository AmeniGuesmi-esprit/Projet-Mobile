import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Inserts an active user directly (no password hashing: tests open
/// sessions through `SessionService`, never through `/auth/login`).
Future<int> insertTestUser(
  Database db,
  String email,
  String role, {
  String prenom = 'Test',
  String nom = 'Utilisateur',
  String statut = 'actif',
}) =>
    db.insert('utilisateur', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': '98000000',
      'mot_de_passe_hash': 'not-a-real-hash',
      'role': role,
      'statut_compte': statut,
      'rib': role == 'client' ? null : '30004000011234567890173',
      'solde_centimes': 0,
      'cree_le': DateTime.now().toIso8601String(),
    });

Future<int> insertTestRequest(
  Database db,
  int patientId, {
  String statut = 'en_attente',
  String urgence = 'moyenne',
  DateTime? creeLe,
}) {
  final at = (creeLe ?? DateTime.now()).toIso8601String();
  return db.insert('teledoc_demande', {
    'motif': 'Motif test',
    'description': 'Description de test suffisante',
    'urgence': urgence,
    'statut': statut,
    'patient_id': patientId,
    'cree_le': at,
    'modifie_le': at,
  });
}
