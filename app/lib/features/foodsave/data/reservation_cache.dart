import 'package:proxilife_shared/proxilife_shared.dart';

/// Copy of the client's FoodSave reservations kept on the phone, so
/// « Mes réservations » and the pickup QR code can still be shown at the
/// shop without network. The server stays the source of truth: the copy is
/// refreshed after every successful call and only read when the server
/// cannot be reached.
///
/// Rows are scoped by user id: two accounts on the same phone never see
/// each other's reservations.
abstract class FoodSaveReservationCache {
  /// Replaces the user's whole list with the server's one.
  Future<void> replaceAll(int userId, List<ReservationDto> list);

  /// Inserts or updates one reservation.
  Future<void> save(int userId, ReservationDto reservation);

  /// Most recent first.
  Future<List<ReservationDto>> all(int userId);

  Future<ReservationDto?> byId(int userId, int id);
}

/// In-memory [FoodSaveReservationCache], for widget tests.
class MemoryReservationCache implements FoodSaveReservationCache {
  final Map<int, Map<int, ReservationDto>> _byUser = {};

  @override
  Future<void> replaceAll(int userId, List<ReservationDto> list) async {
    _byUser[userId] = {for (final r in list) r.id: r};
  }

  @override
  Future<void> save(int userId, ReservationDto reservation) async {
    (_byUser[userId] ??= {})[reservation.id] = reservation;
  }

  @override
  Future<List<ReservationDto>> all(int userId) async =>
      (_byUser[userId]?.values.toList() ?? <ReservationDto>[])
        ..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<ReservationDto?> byId(int userId, int id) async =>
      _byUser[userId]?[id];
}
