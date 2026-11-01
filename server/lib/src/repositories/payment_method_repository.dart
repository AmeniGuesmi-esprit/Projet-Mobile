import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `moyen_paiement`.
class PaymentMethodRepository {
  PaymentMethodRepository(this._db);

  final Database _db;

  Future<List<Map<String, Object?>>> listForUser(int utilisateurId) =>
      _db.query('moyen_paiement',
          where: 'utilisateur_id = ?',
          whereArgs: [utilisateurId],
          orderBy: 'par_defaut DESC, id DESC');

  Future<Map<String, Object?>?> findById(int id) async {
    final rows =
        await _db.query('moyen_paiement', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> countForUser(int utilisateurId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM moyen_paiement WHERE utilisateur_id = ?',
      [utilisateurId],
    );
    return rows.first['c'] as int;
  }

  Future<int> insert({
    required int utilisateurId,
    required PaymentMethodType type,
    String? last4,
    String? titulaire,
    String? dateExpiration,
    required bool parDefaut,
  }) async {
    return _db.transaction((txn) async {
      if (parDefaut) {
        await txn.update('moyen_paiement', {'par_defaut': 0},
            where: 'utilisateur_id = ?', whereArgs: [utilisateurId]);
      }
      return txn.insert('moyen_paiement', {
        'type': type.apiValue,
        'quatre_derniers_chiffres': last4,
        'nom_titulaire': titulaire,
        'date_expiration': dateExpiration,
        'par_defaut': parDefaut ? 1 : 0,
        'utilisateur_id': utilisateurId,
        'cree_le': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> update(
    int id, {
    String? nomTitulaire,
    String? dateExpiration,
  }) =>
      _db.update('moyen_paiement', {
        if (nomTitulaire != null) 'nom_titulaire': nomTitulaire,
        if (dateExpiration != null) 'date_expiration': dateExpiration,
      }, where: 'id = ?', whereArgs: [id]);

  Future<void> setDefault(int id, int utilisateurId) async {
    await _db.transaction((txn) async {
      await txn.update('moyen_paiement', {'par_defaut': 0},
          where: 'utilisateur_id = ?', whereArgs: [utilisateurId]);
      await txn.update('moyen_paiement', {'par_defaut': 1},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> delete(int id) =>
      _db.delete('moyen_paiement', where: 'id = ?', whereArgs: [id]);

  PaymentMethodDto toDto(Map<String, Object?> row) => PaymentMethodDto(
        id: row['id'] as int,
        type: PaymentMethodType.parse(row['type'] as String),
        quatreDerniersChiffres: row['quatre_derniers_chiffres'] as String?,
        nomTitulaire: row['nom_titulaire'] as String?,
        dateExpiration: row['date_expiration'] as String?,
        parDefaut: (row['par_defaut'] as int) == 1,
      );
}
