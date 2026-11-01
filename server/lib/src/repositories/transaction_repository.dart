import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `transaction_`. Lists always join both parties and the
/// payment method so the invoice view can show names, direction and method
/// without extra round-trips.
class TransactionRepository {
  TransactionRepository(this._db);

  final Database _db;

  static const String _selectWithParties =
      'SELECT t.*, u.nom AS b_nom, u.prenom AS b_prenom, u.email AS b_email, '
      'p.nom AS p_nom, p.prenom AS p_prenom, p.email AS p_email, '
      'm.type AS mp_type '
      'FROM transaction_ t '
      'LEFT JOIN utilisateur u ON u.id = t.beneficiaire_id '
      'LEFT JOIN utilisateur p ON p.id = t.utilisateur_id '
      'LEFT JOIN moyen_paiement m ON m.id = t.moyen_paiement_id ';

  /// Transactions where the user is the payer **or** the beneficiary.
  Future<List<Map<String, Object?>>> listForUser(
    int utilisateurId, {
    TransactionStatus? statut,
    ServiceType? service,
  }) {
    final where =
        StringBuffer('(t.utilisateur_id = ? OR t.beneficiaire_id = ?)');
    final args = <Object?>[utilisateurId, utilisateurId];
    if (statut != null) {
      where.write(' AND t.statut = ?');
      args.add(statut.apiValue);
    }
    if (service != null) {
      where.write(' AND t.type_service = ?');
      args.add(service.apiValue);
    }
    return _db.rawQuery(
      '$_selectWithParties WHERE ${where.toString()} ORDER BY t.id DESC',
      args,
    );
  }

  Future<Map<String, Object?>?> findById(int id) async {
    final rows = await _db.rawQuery(
      '$_selectWithParties WHERE t.id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insert(Map<String, Object?> values) =>
      _db.insert('transaction_', values);

  Future<void> updateStatus(int id, TransactionStatus status) => _db.update(
        'transaction_',
        {'statut': status.apiValue},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> delete(int id) =>
      _db.delete('transaction_', where: 'id = ?', whereArgs: [id]);

  /// Maps a joined row to the public DTO. [forUserId] resolves [direction]
  /// from the requesting user's point of view (debit = payer, credit =
  /// beneficiary).
  TransactionDto toDto(Map<String, Object?> row, {int? forUserId}) {
    final beneficiaryName =
        row['b_nom'] == null ? null : '${row['b_prenom']} ${row['b_nom']}';
    final payerName =
        row['p_nom'] == null ? null : '${row['p_prenom']} ${row['p_nom']}';
    TransactionDirection? direction;
    if (forUserId != null) {
      if (row['utilisateur_id'] == forUserId) {
        direction = TransactionDirection.debit;
      } else if (row['beneficiaire_id'] == forUserId) {
        direction = TransactionDirection.credit;
      }
    }
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
      moyenPaiementType: row['mp_type'] == null
          ? null
          : PaymentMethodType.parse(row['mp_type'] as String),
      direction: direction,
      beneficiaireNom: beneficiaryName,
      beneficiaireEmail: row['b_email'] as String?,
      payeurNom: payerName,
      payeurEmail: row['p_email'] as String?,
    );
  }
}
