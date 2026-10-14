import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `teledoc_demande`. Reads join the patient's name and the
/// consultation (if any). Methods accept an optional [DatabaseExecutor] so
/// the service can run them inside a transaction.
class TeledocRequestRepository {
  TeledocRequestRepository(this._db);

  final Database _db;

  static const String _select =
      'SELECT d.*, u.prenom AS p_prenom, u.nom AS p_nom, '
      'c.id AS c_id, c.medecin_id AS c_medecin_id, c.type AS c_type '
      'FROM teledoc_demande d '
      'JOIN utilisateur u ON u.id = d.patient_id '
      'LEFT JOIN teledoc_consultation c ON c.demande_id = d.id';

  Future<Map<String, Object?>?> findById(int id,
      [DatabaseExecutor? executor]) async {
    final rows =
        await (executor ?? _db).rawQuery('$_select WHERE d.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listForPatient(
    int patientId, {
    TeledocRequestStatus? statut,
  }) {
    final where = StringBuffer('d.patient_id = ?');
    final args = <Object?>[patientId];
    if (statut != null) {
      where.write(' AND d.statut = ?');
      args.add(statut.apiValue);
    }
    return _db.rawQuery('$_select WHERE $where ORDER BY d.id DESC', args);
  }

  /// All waiting requests (the queue order itself is computed by
  /// [TeledocQueue], the single source of truth).
  Future<List<Map<String, Object?>>> listWaiting(
          [DatabaseExecutor? executor]) =>
      (executor ?? _db).rawQuery(
        "$_select WHERE d.statut = 'en_attente' ORDER BY d.cree_le, d.id",
      );

  Future<int> countActiveForPatient(int patientId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM teledoc_demande '
      "WHERE patient_id = ? AND statut IN ('en_attente', 'en_cours')",
      [patientId],
    );
    return rows.first['c'] as int;
  }

  Future<int> insert(Map<String, Object?> values) =>
      _db.insert('teledoc_demande', values);

  Future<void> update(int id, Map<String, Object?> values,
          [DatabaseExecutor? executor]) =>
      (executor ?? _db)
          .update('teledoc_demande', values, where: 'id = ?', whereArgs: [id]);

  /// Moves a request from `en_attente` to `en_cours` only if it is still
  /// waiting. Returns false if someone else took it first.
  Future<bool> claimWaiting(
      int id, String at, DatabaseExecutor executor) async {
    final changed = await executor.update(
      'teledoc_demande',
      {'statut': TeledocRequestStatus.enCours.apiValue, 'modifie_le': at},
      where: 'id = ? AND statut = ?',
      whereArgs: [id, TeledocRequestStatus.enAttente.apiValue],
    );
    return changed == 1;
  }

  Future<void> delete(int id) =>
      _db.delete('teledoc_demande', where: 'id = ?', whereArgs: [id]);

  static TeledocQueueEntry toQueueEntry(Map<String, Object?> row) =>
      TeledocQueueEntry(
        id: row['id'] as int,
        urgence: TeledocUrgency.parse(row['urgence'] as String),
        creeLe: DateTime.parse(row['cree_le'] as String),
      );

  /// [place] is only provided for waiting requests.
  TeledocRequestDto toDto(Map<String, Object?> row,
          {TeledocQueuePlace? place}) =>
      TeledocRequestDto(
        id: row['id'] as int,
        motif: row['motif'] as String,
        description: row['description'] as String,
        urgence: TeledocUrgency.parse(row['urgence'] as String),
        aPhoto: row['photo_symptome'] != null,
        statut: TeledocRequestStatus.parse(row['statut'] as String),
        positionFile: place?.position,
        tempsEstimeMinutes: place?.waitMinutes,
        patientNom: '${row['p_prenom']} ${row['p_nom']}',
        transactionId: row['transaction_id'] as int?,
        consultationId: row['c_id'] as int?,
        creeLe: row['cree_le'] as String,
        modifieLe: row['modifie_le'] as String,
      );
}
