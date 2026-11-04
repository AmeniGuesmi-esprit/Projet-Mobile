import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `teledoc_consultation`. Reads join the request summary,
/// the patient, the doctor and the pharmacy so the history screens need a
/// single call.
class TeledocConsultationRepository {
  TeledocConsultationRepository(this._db);

  final Database _db;

  static const String _select =
      'SELECT c.*, d.motif AS d_motif, d.urgence AS d_urgence, '
      'd.statut AS d_statut, d.patient_id AS d_patient_id, '
      'pu.prenom AS p_prenom, pu.nom AS p_nom, '
      'mu.prenom AS m_prenom, mu.nom AS m_nom, ph.nom AS ph_nom '
      'FROM teledoc_consultation c '
      'JOIN teledoc_demande d ON d.id = c.demande_id '
      'JOIN utilisateur pu ON pu.id = d.patient_id '
      'LEFT JOIN utilisateur mu ON mu.id = c.medecin_id '
      'LEFT JOIN teledoc_pharmacie ph ON ph.id = c.pharmacie_id';

  static const String _newestFirst = 'ORDER BY c.date_debut DESC, c.id DESC';

  Future<Map<String, Object?>?> findById(int id,
      [DatabaseExecutor? executor]) async {
    final rows =
        await (executor ?? _db).rawQuery('$_select WHERE c.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listForDoctor(int doctorId) =>
      _db.rawQuery('$_select WHERE c.medecin_id = ? $_newestFirst', [doctorId]);

  Future<List<Map<String, Object?>>> listForPatient(int patientId) => _db
      .rawQuery('$_select WHERE d.patient_id = ? $_newestFirst', [patientId]);

  Future<Map<String, Object?>?> findOpenForDoctor(int doctorId,
      [DatabaseExecutor? executor]) async {
    final rows = await (executor ?? _db).rawQuery(
        '$_select WHERE c.medecin_id = ? AND c.date_fin IS NULL', [doctorId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Durations of the most recent consultations that really took place
  /// (request `terminee`), used for the dynamic wait estimate.
  Future<List<Duration>> recentDurations(int limit,
      [DatabaseExecutor? executor]) async {
    final rows = await (executor ?? _db).rawQuery(
      'SELECT c.date_debut, c.date_fin FROM teledoc_consultation c '
      'JOIN teledoc_demande d ON d.id = c.demande_id '
      "WHERE c.date_fin IS NOT NULL AND d.statut = 'terminee' "
      'ORDER BY c.date_fin DESC LIMIT ?',
      [limit],
    );
    return rows
        .map((r) => DateTime.parse(r['date_fin'] as String)
            .difference(DateTime.parse(r['date_debut'] as String)))
        .toList();
  }

  Future<int> insert(Map<String, Object?> values,
          [DatabaseExecutor? executor]) =>
      (executor ?? _db).insert('teledoc_consultation', values);

  Future<void> update(int id, Map<String, Object?> values,
          [DatabaseExecutor? executor]) =>
      (executor ?? _db).update('teledoc_consultation', values,
          where: 'id = ?', whereArgs: [id]);

  Future<void> delete(int id, [DatabaseExecutor? executor]) => (executor ?? _db)
      .delete('teledoc_consultation', where: 'id = ?', whereArgs: [id]);

  TeledocConsultationDto toDto(Map<String, Object?> row) =>
      TeledocConsultationDto(
        id: row['id'] as int,
        dateDebut: row['date_debut'] as String,
        dateFin: row['date_fin'] as String?,
        type: TeledocConsultationType.parse(row['type'] as String),
        ordonnance: row['ordonnance'] as String?,
        idPharmacie: row['pharmacie_id'] as int?,
        pharmacieNom: row['ph_nom'] as String?,
        idDemande: row['demande_id'] as int,
        idMedecin: row['medecin_id'] as int?,
        medecinNom:
            row['m_nom'] == null ? null : '${row['m_prenom']} ${row['m_nom']}',
        patientNom: '${row['p_prenom']} ${row['p_nom']}',
        motif: row['d_motif'] as String,
        urgence: TeledocUrgency.parse(row['d_urgence'] as String),
        statutDemande: TeledocRequestStatus.parse(row['d_statut'] as String),
        // The room only opens the call while the consultation is running.
        salleAppel:
            row['date_fin'] == null ? row['salle_appel'] as String? : null,
      );
}
