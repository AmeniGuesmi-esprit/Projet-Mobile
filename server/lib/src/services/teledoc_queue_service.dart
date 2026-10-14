import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/teledoc_consultation_repository.dart';
import '../repositories/teledoc_request_repository.dart';

/// The waiting queue at one instant: rows in queue order, with each one's
/// position and estimated wait (CONCEPTION.md §5).
class TeledocQueueSnapshot {
  const TeledocQueueSnapshot({
    required this.ordered,
    required this.places,
    required this.doctors,
    required this.averageMinutes,
  });

  /// Waiting request rows, head first.
  final List<Map<String, Object?>> ordered;
  final Map<int, TeledocQueuePlace> places;
  final int doctors;
  final int averageMinutes;

  int get size => ordered.length;

  TeledocQueuePlace? placeOf(int requestId) => places[requestId];
}

/// Builds queue snapshots. Nothing is stored: positions and waits are
/// recomputed from the database on every read (decision D2), so they are
/// always up to date after a cancellation, an urgent arrival, a consultation
/// start or a change of the average consultation length.
class TeledocQueueService {
  TeledocQueueService({
    required Database db,
    required this.requests,
    required this.consultations,
  }) : _db = db;

  final Database _db;
  final TeledocRequestRepository requests;
  final TeledocConsultationRepository consultations;

  /// [executor] lets the service read the queue inside a transaction (taking
  /// the head of the queue must see a consistent state).
  Future<TeledocQueueSnapshot> snapshot([DatabaseExecutor? executor]) async {
    final rows = await requests.listWaiting(executor);
    final doctors = await _countActiveDoctors(executor ?? _db);
    final averageMinutes = TeledocQueue.averageDurationMinutes(
      await consultations.recentDurations(
          TeledocQueue.durationSampleSize, executor),
    );
    final places = TeledocQueue.places(
      rows.map(TeledocRequestRepository.toQueueEntry),
      doctors: doctors,
      averageMinutes: averageMinutes,
    );
    final ordered = [...rows]..sort((a, b) => places[a['id'] as int]!
        .position
        .compareTo(places[b['id'] as int]!.position));
    return TeledocQueueSnapshot(
      ordered: ordered,
      places: places,
      doctors: doctors,
      averageMinutes: averageMinutes,
    );
  }

  /// Active `medecin` accounts (read-only access to the User module's table).
  Future<int> _countActiveDoctors(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM utilisateur WHERE role = ? AND statut_compte = ?',
      [UserRole.medecin.apiValue, AccountStatus.actif.apiValue],
    );
    return rows.first['c'] as int;
  }
}
