import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';

/// User-facing message of an error (server messages are already in French).
String apiErrorMessage(
  Object error, {
  String fallback = 'Une erreur est survenue, veuillez réessayer',
}) =>
    error is ApiException ? error.message : fallback;

/// Reservation endpoints over [ApiClient].
class ReservationApi {
  ReservationApi(this._client);

  final ApiClient _client;

  /// Passenger: asks for [nbPlaces] seats on a trip.
  Future<TripReservationDto> request({
    required int tripId,
    required int nbPlaces,
  }) async {
    final data = await _client
        .postJson('/trips/$tripId/reservations', {'nb_places': nbPlaces});
    return TripReservationDto.fromJson(data);
  }

  /// Passenger: his own reservations.
  Future<List<TripReservationDto>> mine() => _list('/reservations/mine');

  /// Driver: requests received on his trips (pending first).
  Future<List<TripReservationDto>> received() => _list('/reservations/received');

  Future<TripReservationDto> accept(int id) => _action(id, 'accept');
  Future<TripReservationDto> refuse(int id) => _action(id, 'refuse');
  Future<TripReservationDto> cancel(int id) => _action(id, 'cancel');

  /// Driver: current boarding code (QR payload) of one of his trips.
  Future<BoardingCodeDto> boardingCode(int tripId) async {
    final data = await _client.getJson('/trips/$tripId/boarding-code');
    return BoardingCodeDto.fromJson(data);
  }

  /// Passenger: confirms boarding with the code read from the driver.
  Future<TripReservationDto> confirmBoarding({
    required int reservationId,
    required String code,
    required BoardingMethod method,
    required double lat,
    required double lng,
  }) async {
    final data = await _client.postJson('/reservations/$reservationId/board', {
      'code': code,
      'methode': method.apiValue,
      'lat': lat,
      'lng': lng,
    });
    return TripReservationDto.fromJson(data);
  }

  Future<List<TripReservationDto>> _list(String path) async {
    final data = await _client.getJson(path);
    return (data['items'] as List)
        .map((e) => TripReservationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TripReservationDto> _action(int id, String action) async {
    final data = await _client.postJson('/reservations/$id/$action');
    return TripReservationDto.fromJson(data);
  }
}
