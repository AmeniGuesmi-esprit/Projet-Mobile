import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';

/// Fields of a session, as typed by the coach in the form.
class CoachSessionForm {
  const CoachSessionForm({
    required this.titre,
    this.description,
    required this.type,
    required this.niveau,
    required this.lieu,
    required this.latitude,
    required this.longitude,
    required this.dateHeure,
    required this.dureeMinutes,
    required this.places,
    required this.prixCentimes,
  });

  final String titre;
  final String? description;
  final CoachSessionType type;
  final CoachLevel niveau;
  final String lieu;
  final double latitude;
  final double longitude;
  final DateTime dateHeure;
  final int dureeMinutes;
  final int places;
  final int prixCentimes;

  Map<String, dynamic> toJson() => {
        'titre': titre,
        'description': description,
        'type': type.apiValue,
        'niveau': niveau.apiValue,
        'lieu': lieu,
        'latitude': latitude,
        'longitude': longitude,
        'date_heure': dateHeure.toUtc().toIso8601String(),
        'duree_minutes': dureeMinutes,
        'places': places,
        'prix_centimes': prixCentimes,
      };
}

/// Typed CoachProche endpoints over [ApiClient]. Dates are sent in UTC.
class CoachApi {
  CoachApi(this._client);

  final ApiClient _client;

  static List<T> _items<T>(
          Map<String, dynamic> data, T Function(Map<String, dynamic>) f) =>
      (data['items'] as List).map((e) => f(e as Map<String, dynamic>)).toList();

  // ------------------------------------------------------------- sessions

  /// Upcoming sessions. With a position the server computes the distance
  /// (and sorts by distance when [sortByDistance] is set).
  Future<List<CoachSessionDto>> search({
    CoachSessionType? type,
    CoachLevel? niveau,
    String? lieu,
    DateTime? from,
    DateTime? to,
    int? prixMaxCentimes,
    double? latitude,
    double? longitude,
    double? rayonKm,
    bool sortByDistance = false,
  }) async {
    final params = <String, String>{
      if (type != null) 'type': type.apiValue,
      if (niveau != null) 'niveau': niveau.apiValue,
      if (lieu != null && lieu.trim().isNotEmpty) 'lieu': lieu.trim(),
      if (from != null) 'date_debut': from.toUtc().toIso8601String(),
      if (to != null) 'date_fin': to.toUtc().toIso8601String(),
      if (prixMaxCentimes != null) 'prix_max_centimes': '$prixMaxCentimes',
      if (latitude != null) 'lat': '$latitude',
      if (longitude != null) 'lng': '$longitude',
      if (rayonKm != null) 'rayon_km': '$rayonKm',
      if (sortByDistance) 'tri': 'distance',
    };
    final query = Uri(queryParameters: params).query;
    final data =
        await _client.getJson('/coach/seances${query.isEmpty ? '' : '?$query'}');
    return _items(data, CoachSessionDto.fromJson);
  }

  Future<CoachSessionDto> getSession(int id) async =>
      CoachSessionDto.fromJson(await _client.getJson('/coach/seances/$id'));

  Future<List<CoachSessionDto>> mySessions() async =>
      _items(await _client.getJson('/coach/mes-seances'),
          CoachSessionDto.fromJson);

  Future<CoachSessionDto> publish(CoachSessionForm form) async =>
      CoachSessionDto.fromJson(
          await _client.postJson('/coach/seances', form.toJson()));

  Future<CoachSessionDto> update(int id, CoachSessionForm form) async =>
      CoachSessionDto.fromJson(
          await _client.putJson('/coach/seances/$id', form.toJson()));

  Future<CoachSessionDto> cancelSession(int id) async =>
      CoachSessionDto.fromJson(
          await _client.postJson('/coach/seances/$id/cancel'));

  Future<List<CoachBookingDto>> attendees(int sessionId) async =>
      _items(await _client.getJson('/coach/seances/$sessionId/inscrits'),
          CoachBookingDto.fromJson);

  // ------------------------------------------------------------- bookings

  Future<CoachBookingDto> reserve(int sessionId, {int? paymentMethodId}) async =>
      CoachBookingDto.fromJson(await _client.postJson('/coach/reservations', {
        'seance_id': sessionId,
        'moyen_paiement_id': paymentMethodId,
      }));

  Future<List<CoachBookingDto>> myBookings() async =>
      _items(await _client.getJson('/coach/reservations'),
          CoachBookingDto.fromJson);

  Future<CoachBookingDto> getBooking(int id) async =>
      CoachBookingDto.fromJson(await _client.getJson('/coach/reservations/$id'));

  Future<CoachBookingDto> cancelBooking(int id) async =>
      CoachBookingDto.fromJson(
          await _client.postJson('/coach/reservations/$id/cancel'));

  /// Steps and / or heart rate of a session already attended.
  Future<CoachBookingDto> saveMetrics(int id,
          {int? pas, int? frequenceCardiaque}) async =>
      CoachBookingDto.fromJson(
          await _client.putJson('/coach/reservations/$id/suivi', {
        'pas': pas,
        'frequence_cardiaque': frequenceCardiaque,
      }));

  // ----------------------------------------------------------------- scan

  Future<CoachScanResultDto> scan(String token) async =>
      CoachScanResultDto.fromJson(
          await _client.postJson('/coach/scan', {'token': token}));

  // -------------------------------------------------------- notifications

  Future<List<CoachNotificationDto>> notifications(
      {bool unreadOnly = false}) async {
    final data = await _client
        .getJson('/coach/notifications${unreadOnly ? '?non_lues=1' : ''}');
    return _items(data, CoachNotificationDto.fromJson);
  }

  Future<void> markAllRead() async {
    await _client.postJson('/coach/notifications/read-all');
  }
}
