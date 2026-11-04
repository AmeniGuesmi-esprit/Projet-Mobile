import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `reservation`. Methods that take a [DatabaseExecutor] are
/// meant to run inside a transaction (the executor is then the transaction).
class ReservationRepository {
  ReservationRepository(this._db);

  final Database _db;

  Future<Map<String, Object?>?> findById(
    int id, {
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? _db)
        .query('reservation_trajet', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// True when the passenger already has a pending or accepted request on the
  /// trip.
  Future<bool> hasActive(
    DatabaseExecutor executor,
    int tripId,
    int passagerId,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM reservation_trajet WHERE trajet_id = ? '
      "AND passager_id = ? AND statut IN ('en_attente', 'acceptee')",
      [tripId, passagerId],
    );
    return (rows.first['c'] as int) > 0;
  }

  Future<int> insert(
    DatabaseExecutor executor, {
    required int tripId,
    required int passagerId,
    required int nbPlaces,
  }) =>
      executor.insert('reservation_trajet', {
        'trajet_id': tripId,
        'passager_id': passagerId,
        'nb_places': nbPlaces,
        'statut': TripReservationStatus.enAttente.apiValue,
        'date_reservation': DateTime.now().toIso8601String(),
      });

  Future<void> setStatus(
    DatabaseExecutor executor,
    int id,
    TripReservationStatus status,
  ) =>
      executor.update(
        'reservation_trajet',
        {
          'statut': status.apiValue,
          'date_decision': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Reservations made by a passenger, newest first.
  Future<List<Map<String, Object?>>> listForPassenger(int passagerId) =>
      _db.query(
        'reservation_trajet',
        where: 'passager_id = ?',
        whereArgs: [passagerId],
        orderBy: 'id DESC',
      );

  /// Requests received by a driver (all his trips): pending ones first.
  Future<List<Map<String, Object?>>> listForDriver(int conducteurId) =>
      _db.rawQuery('''
SELECT r.* FROM reservation_trajet r
JOIN trajet t ON t.id = r.trajet_id
WHERE t.conducteur_id = ?
ORDER BY CASE r.statut WHEN 'en_attente' THEN 0 ELSE 1 END, r.id DESC
''', [conducteurId]);
}
