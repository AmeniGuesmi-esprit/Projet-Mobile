import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `transaction_`. Lists always join the beneficiary so the
/// invoice view can show names without an extra round-trip.
class TransactionRepository {
  TransactionRepository(this._db);

  final Database _db;

  Future<List<Map<String, Object?>>> listForUser(
    int utilisateurId, {
    TransactionStatus? statut,
    ServiceType? service,
  }) {
    final where = StringBuffer('t.utilisateur_id = ?');
    final args = <Object?>[utilisateurId];
    if (statut != null) {
      where.write(' AND t.statut = ?');
      args.add(statut.apiValue);
    }
    if (service != null) {
      where.write(' AND t.type_service = ?');
      args.add(service.apiValue);
    }
    return _db.rawQuery(
      'SELECT t.*, u.nom AS b_nom, u.prenom AS b_prenom, u.email AS b_email '
      'FROM transaction_ t LEFT JOIN utilisateur u ON u.id = t.beneficiaire_id '
      'WHERE ${where.toString()} ORDER BY t.id DESC',
      args,
    );
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final rows = await _db.rawQuery(
      'SELECT t.*, u.nom AS b_nom, u.prenom AS b_prenom, u.email AS b_email '
      'FROM transaction_ t LEFT JOIN utilisateur u ON u.id = t.beneficiaire_id '
      'WHERE t.id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insert(Map<String, Object?> values) =>
      _db.insert('transaction_', values);

  Future<void> delete(int id) =>
      _db.delete('transaction_', where: 'id = ?', whereArgs: [id]);

  TransactionDto toDto(Map<String, Object?> row) {
    final beneficiaryName = row['b_nom'] == null
        ? null
        : '${row['b_prenom']} ${row['b_nom']}';
    return TransactionDto(
      id: row['id'] as int,
      montantCentimes: row['montant_centimes'] as int,
      devise: row['devise'] as String,
      dateIso: row['date'] as String,
      statut: TransactionStatus.parse(row['statut'] as String),
      typeService: ServiceType.parse(row['type_service'] as String),
      idReference: row['id_reference'] as String?,
      factureNumero: row['facture_numero'] as String,
      idMoyenPaiement: row['moyen_paiement_id'] as int?,
      beneficiaireNom: beneficiaryName,
      beneficiaireEmail: row['b_email'] as String?,
    );
  }
}
