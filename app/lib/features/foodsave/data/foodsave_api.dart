import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';

/// Typed FoodSave endpoints over [ApiClient]. All dates are sent in UTC.
class FoodSaveApi {
  FoodSaveApi(this._client, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final ApiClient _client;
  final http.Client _http;

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  static List<T> _items<T>(
          Map<String, dynamic> data, T Function(Map<String, dynamic>) f) =>
      (data['items'] as List).map((e) => f(e as Map<String, dynamic>)).toList();

  // ---------------------------------------------------------------- images

  /// Absolute URL of a basket photo (auth required → use [imageHeaders]).
  String imageUrl(String image) => '${_client.baseUrl}/foodsave/images/$image';

  Map<String, String> get imageHeaders => {
        if (_client.token != null) 'authorization': 'Bearer ${_client.token}',
      };

  // ----------------------------------------------------------------- store

  /// The merchant's store, or null when not configured yet (404).
  Future<StoreDto?> getMyStore() async {
    try {
      return StoreDto.fromJson(await _client.getJson('/foodsave/store'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<StoreDto> saveMyStore({
    required String nom,
    required String adresse,
    required double latitude,
    required double longitude,
    required FoodCategory categorie,
  }) async =>
      StoreDto.fromJson(await _client.putJson('/foodsave/store', {
        'nom': nom,
        'adresse': adresse,
        'latitude': latitude,
        'longitude': longitude,
        'categorie': categorie.apiValue,
      }));

  /// Postal address of a GPS position (OpenStreetMap, via the server), or
  /// null when unknown / unavailable.
  Future<String?> addressAt(double latitude, double longitude) async {
    try {
      final json = await _client
          .getJson('/foodsave/geo/reverse?lat=$latitude&lng=$longitude');
      final adresse = json['adresse'];
      return adresse is String && adresse.trim().isNotEmpty ? adresse : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 503) return null;
      rethrow;
    }
  }

  // ------------------------------------------------------ merchant baskets

  Future<List<BasketDto>> listMyBaskets({BasketStatus? statut}) async {
    final q = statut == null ? '' : '?statut=${statut.apiValue}';
    return _items(await _client.getJson('/foodsave/merchant/baskets$q'),
        BasketDto.fromJson);
  }

  Future<BasketDto> getMyBasket(int id) async =>
      BasketDto.fromJson(await _client.getJson('/foodsave/merchant/baskets/$id'));

  /// Creates and publishes a basket. Returns the basket and how many nearby
  /// clients were notified.
  Future<({BasketDto panier, int clientsNotifies})> createBasket({
    required String titre,
    required String contenu,
    required FoodCategory categorie,
    required int prixCentimes,
    required int prixInitialCentimes,
    required int quantite,
    required DateTime creneauRetraitDebut,
    required DateTime creneauRetraitFin,
    required DateTime dateExpiration,
  }) async {
    final data = await _client.postJson('/foodsave/merchant/baskets', {
      'titre': titre,
      'contenu': contenu,
      'categorie': categorie.apiValue,
      'prix_centimes': prixCentimes,
      'prix_initial_centimes': prixInitialCentimes,
      'quantite': quantite,
      'creneau_retrait_debut': _iso(creneauRetraitDebut),
      'creneau_retrait_fin': _iso(creneauRetraitFin),
      'date_expiration': _iso(dateExpiration),
    });
    return (
      panier: BasketDto.fromJson(data['panier'] as Map<String, dynamic>),
      clientsNotifies: data['clients_notifies'] as int,
    );
  }

  /// Partial update: only non-null fields are sent.
  Future<BasketDto> updateBasket(
    int id, {
    String? titre,
    String? contenu,
    FoodCategory? categorie,
    int? prixCentimes,
    int? prixInitialCentimes,
    int? quantite,
    DateTime? creneauRetraitDebut,
    DateTime? creneauRetraitFin,
    DateTime? dateExpiration,
  }) async =>
      BasketDto.fromJson(
          await _client.patchJson('/foodsave/merchant/baskets/$id', {
        'titre': ?titre,
        'contenu': ?contenu,
        'categorie': ?categorie?.apiValue,
        'prix_centimes': ?prixCentimes,
        'prix_initial_centimes': ?prixInitialCentimes,
        'quantite': ?quantite,
        if (creneauRetraitDebut != null)
          'creneau_retrait_debut': _iso(creneauRetraitDebut),
        if (creneauRetraitFin != null)
          'creneau_retrait_fin': _iso(creneauRetraitFin),
        if (dateExpiration != null) 'date_expiration': _iso(dateExpiration),
      }));

  /// Cancels the basket and its active reservations (clients are notified,
  /// paid reservations refunded when possible).
  Future<BasketDto> cancelBasket(int id) async => BasketDto.fromJson(
      await _client.postJson('/foodsave/merchant/baskets/$id/cancel'));

  /// Hard delete — only allowed when the basket never had a reservation.
  Future<void> deleteBasket(int id) =>
      _client.deleteJson('/foodsave/merchant/baskets/$id');

  /// Uploads a JPEG/PNG photo (≤ 2 Mo) as the raw request body.
  Future<BasketDto> uploadBasketImage(
      int id, List<int> bytes, String contentType) async {
    final response = await _http
        .post(
          Uri.parse('${_client.baseUrl}/foodsave/merchant/baskets/$id/image'),
          headers: {...imageHeaders, 'content-type': contentType},
          body: bytes,
        )
        .timeout(const Duration(seconds: 20));
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode,
          decoded['error'] as String? ?? 'Envoi de la photo impossible');
    }
    return BasketDto.fromJson(decoded);
  }

  Future<MerchantStatsDto> merchantStats() async =>
      MerchantStatsDto.fromJson(
          await _client.getJson('/foodsave/merchant/stats'));

  Future<List<ReservationDto>> merchantReservations(
      {int? panierId, ReservationStatus? statut}) async {
    final q = [
      if (panierId != null) 'panier_id=$panierId',
      if (statut != null) 'statut=${statut.apiValue}',
    ].join('&');
    return _items(
        await _client
            .getJson('/foodsave/merchant/reservations${q.isEmpty ? '' : '?$q'}'),
        ReservationDto.fromJson);
  }

  /// Validates a pickup. Refusals come back as a normal [ScanResultDto]
  /// (accepte == false) with a French explanation, not as exceptions.
  Future<ScanResultDto> scan(String token) async => ScanResultDto.fromJson(
      await _client.postJson('/foodsave/merchant/scan', {'token': token}));

  // ------------------------------------------------------- client catalog

  /// Available baskets. Without [latitude]/[longitude] the server uses the
  /// client's last stored position (distance null when unknown).
  Future<List<BasketDto>> listBaskets({
    double? latitude,
    double? longitude,
    double? rayonKm,
    FoodCategory? categorie,
    String? recherche,
    BasketSort tri = BasketSort.distance,
  }) async {
    final q = <String>[
      if (latitude != null) 'lat=$latitude',
      if (longitude != null) 'lng=$longitude',
      if (rayonKm != null) 'rayon_km=$rayonKm',
      if (categorie != null) 'categorie=${categorie.apiValue}',
      if (recherche != null && recherche.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(recherche.trim())}',
      'tri=${tri.apiValue}',
    ].join('&');
    return _items(
        await _client.getJson('/foodsave/baskets?$q'), BasketDto.fromJson);
  }

  /// Any basket by id, with its real status (even if sold out / cancelled).
  Future<BasketDto> getBasket(int id) async =>
      BasketDto.fromJson(await _client.getJson('/foodsave/baskets/$id'));

  // ------------------------------------------------------------- location

  Future<void> updateMyLocation(double latitude, double longitude) =>
      _client.putJson('/foodsave/location',
          {'latitude': latitude, 'longitude': longitude});

  /// Forget the stored position (client refused geolocation).
  Future<void> clearMyLocation() => _client.deleteJson('/foodsave/location');

  // --------------------------------------------------------- reservations

  /// Reserves and pays. On success the reservation is `en_attente` with a
  /// `qrToken`; on payment failure the server answers with an error.
  Future<ReservationDto> reserve({
    required int panierId,
    required int quantite,
    required int moyenPaiementId,
  }) async =>
      ReservationDto.fromJson(await _client.postJson('/foodsave/reservations', {
        'panier_id': panierId,
        'quantite': quantite,
        'moyen_paiement_id': moyenPaiementId,
      }));

  Future<List<ReservationDto>> myReservations() async => _items(
      await _client.getJson('/foodsave/reservations'), ReservationDto.fromJson);

  Future<ReservationDto> getReservation(int id) async => ReservationDto.fromJson(
      await _client.getJson('/foodsave/reservations/$id'));

  Future<ReservationDto> cancelReservation(int id) async =>
      ReservationDto.fromJson(
          await _client.postJson('/foodsave/reservations/$id/cancel'));

  // -------------------------------------------------------- notifications

  Future<List<FoodSaveNotificationDto>> notifications(
      {bool unreadOnly = false}) async {
    final q = unreadOnly ? '?non_lues=1' : '';
    return _items(await _client.getJson('/foodsave/notifications$q'),
        FoodSaveNotificationDto.fromJson);
  }

  Future<void> markNotificationRead(int id) =>
      _client.postJson('/foodsave/notifications/$id/read');

  Future<void> markAllNotificationsRead() =>
      _client.postJson('/foodsave/notifications/read-all');
}
