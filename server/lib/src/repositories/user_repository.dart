import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for the `utilisateur` table.
class UserRepository {
  UserRepository(this._db);

  final Database _db;

  Future<Map<String, Object?>?> findByEmail(String email) async {
    final rows = await _db.query(
      'utilisateur',
      where: 'email = ?',
      whereArgs: [normalizeEmail(email)],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final rows = await _db.query('utilisateur', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insert({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String motDePasseHash,
    required UserRole role,
    String? rib,
  }) {
    return _db.insert('utilisateur', {
      'nom': nom,
      'prenom': prenom,
      'email': normalizeEmail(email),
      'telephone': telephone,
      'mot_de_passe_hash': motDePasseHash,
      'photo': null,
      'role': role.apiValue,
      'statut_compte': AccountStatus.enAttenteVerification.apiValue,
      'rib': rib == null ? null : normalizeRib(rib),
      'solde_centimes': 0,
      'cree_le': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateProfile(
    int id, {
    String? nom,
    String? prenom,
    String? telephone,
    String? photo,
    String? rib,
    bool clearPhoto = false,
    bool clearRib = false,
  }) async {
    final values = <String, Object?>{};
    if (nom != null) values['nom'] = nom;
    if (prenom != null) values['prenom'] = prenom;
    if (telephone != null) values['telephone'] = telephone;
    if (photo != null) values['photo'] = photo;
    if (clearPhoto) values['photo'] = null;
    if (rib != null) values['rib'] = normalizeRib(rib);
    if (clearRib) values['rib'] = null;
    if (values.isEmpty) return;
    await _db.update('utilisateur', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStatus(int id, AccountStatus status) => _db.update(
        'utilisateur',
        {'statut_compte': status.apiValue},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> setSolde(int id, int soldeCentimes) => _db.update(
        'utilisateur',
        {'solde_centimes': soldeCentimes},
        where: 'id = ?',
        whereArgs: [id],
      );

  int soldeOf(Map<String, Object?> row) => row['solde_centimes'] as int;

  /// Deletes the account after anonymising its transactions. Related rows in
  /// moyen_paiement / session / code_verification cascade.
  Future<void> deleteAccount(int id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'transaction_',
        {'utilisateur_id': null},
        where: 'utilisateur_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'transaction_',
        {'beneficiaire_id': null},
        where: 'beneficiaire_id = ?',
        whereArgs: [id],
      );
      await txn.delete('utilisateur', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<bool> hasPendingTransactions(int id) async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM transaction_ WHERE statut = 'en_attente' "
      'AND (utilisateur_id = ? OR beneficiaire_id = ?)',
      [id, id],
    );
    return (rows.first['c'] as int) > 0;
  }

  /// Maps a DB row to the public DTO (no password hash, masked RIB).
  UserDto toDto(Map<String, Object?> row) {
    final rib = row['rib'] as String?;
    return UserDto(
      id: row['id'] as int,
      nom: row['nom'] as String,
      prenom: row['prenom'] as String,
      email: row['email'] as String,
      telephone: row['telephone'] as String,
      photo: row['photo'] as String?,
      role: UserRole.parse(row['role'] as String),
      statutCompte: AccountStatus.parse(row['statut_compte'] as String),
      ribMasque: rib == null
          ? null
          : 'RIB •••• •••• •••• •• ${rib.substring(rib.length - 4)}',
      soldeCentimes: row['solde_centimes'] as int,
    );
  }
}
