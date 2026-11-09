import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';

/// HTTP calls of the ServiceNow module.
class ServiceNowApi {
  ServiceNowApi(this._client);

  final ApiClient _client;

  Future<List<DemandeServiceDto>> myDemandes() =>
      _list('/service-now/demandes/mine');

  Future<List<DemandeServiceDto>> availableDemandes() =>
      _list('/service-now/demandes/disponibles');

  Future<List<DemandeServiceDto>> myInterventions() =>
      _list('/service-now/interventions/mine');

  Future<DemandeServiceDto> demande(int id) async =>
      DemandeServiceDto.fromJson(
          await _client.getJson('/service-now/demandes/$id'));

  Future<DemandeServiceDto> create({
    required ServiceNowType type,
    required String description,
    required String adresse,
    required DateTime dateSouhaitee,
    double? latitude,
    double? longitude,
  }) async =>
      DemandeServiceDto.fromJson(
        await _client.postJson('/service-now/demandes', {
          'type': type.apiValue,
          'description': description,
          'adresse': adresse,
          'date_souhaitee': _utc(dateSouhaitee),
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

  Future<DemandeServiceDto> update(
    int id, {
    required ServiceNowType type,
    required String description,
    required String adresse,
    required DateTime dateSouhaitee,
    double? latitude,
    double? longitude,
  }) async =>
      DemandeServiceDto.fromJson(
        await _client.patchJson('/service-now/demandes/$id', {
          'type': type.apiValue,
          'description': description,
          'adresse': adresse,
          'date_souhaitee': _utc(dateSouhaitee),
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

  Future<DemandeServiceDto> cancel(int id) =>
      _post('/service-now/demandes/$id/annuler');

  Future<DemandeServiceDto> accept(
    int id, {
    required DateTime datePrevue,
    required int prixCentimes,
  }) =>
      _post('/service-now/demandes/$id/accepter', {
        'date_prevue': _utc(datePrevue),
        'prix_centimes': prixCentimes,
      });

  /// [qrCode] is the code shown on the client's phone.
  Future<DemandeServiceDto> start(int interventionId, String qrCode) =>
      _post('/service-now/interventions/$interventionId/demarrer', {
        'qr_code': qrCode,
      });

  Future<DemandeServiceDto> finish(
    int interventionId, {
    required String rapport,
    required int prixCentimes,
  }) =>
      _post('/service-now/interventions/$interventionId/terminer', {
        'rapport': rapport,
        'prix_centimes': prixCentimes,
      });

  Future<DemandeServiceDto> withdraw(int interventionId) =>
      _post('/service-now/interventions/$interventionId/desister');

  Future<DemandeServiceDto> pay(int interventionId, int moyenPaiementId) =>
      _post('/service-now/interventions/$interventionId/payer', {
        'moyen_paiement_id': moyenPaiementId,
      });

  Future<DemandeServiceDto> rate(
    int interventionId, {
    required int note,
    String? commentaire,
  }) =>
      _post('/service-now/interventions/$interventionId/evaluer', {
        'note': note,
        'commentaire': commentaire,
      });

  Future<DemandeServiceDto> startTrip(
    int interventionId, {
    required double latitude,
    required double longitude,
  }) =>
      _post('/service-now/interventions/$interventionId/en-route', {
        'latitude': latitude,
        'longitude': longitude,
      });

  Future<void> updatePosition(
    int interventionId, {
    required double latitude,
    required double longitude,
  }) async {
    await _client.putJson('/service-now/interventions/$interventionId/position',
        {'latitude': latitude, 'longitude': longitude});
  }

  Future<ServiceTrackingDto> tracking(int interventionId) async =>
      ServiceTrackingDto.fromJson(await _client
          .getJson('/service-now/interventions/$interventionId/suivi'));

  Future<DemandeServiceDto> addPhoto(
    int interventionId,
    InterventionPhotoKind kind,
    String base64Data,
  ) =>
      _post('/service-now/interventions/$interventionId/photos', {
        'type': kind.apiValue,
        'photo_base64': base64Data,
      });

  /// Address and headers to show a photo with `Image.network`.
  ({String url, Map<String, String> headers}) photoSource(
    int interventionId,
    InterventionPhotoKind kind,
  ) =>
      (
        url: '${_client.baseUrl}/service-now/interventions/$interventionId'
            '/photos/${kind.apiValue}',
        headers: {
          if (_client.token != null)
            'authorization': 'Bearer ${_client.token}',
        },
      );

  Future<List<NearbyPrestataireDto>> nearbyPrestataires(int demandeId) async {
    final data =
        await _client.getJson('/service-now/demandes/$demandeId/prestataires');
    return (data['items'] as List)
        .map((e) => NearbyPrestataireDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// One search per button press (the address service forbids live search).
  Future<List<GeocodeResultDto>> searchAddress(String query) async {
    final data = await _client.getJson(
        '/service-now/adresses?q=${Uri.encodeQueryComponent(query)}');
    return (data['items'] as List)
        .map((e) => GeocodeResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PriceEstimateDto> estimate(ServiceNowType type) async =>
      PriceEstimateDto.fromJson(await _client
          .getJson('/service-now/estimation?type=${type.apiValue}'));

  Future<PrestataireProfilDto> profile() async =>
      PrestataireProfilDto.fromJson(await _client.getJson('/service-now/profil'));

  Future<PrestataireProfilDto> saveProfile(PrestataireProfilDto profile) async =>
      PrestataireProfilDto.fromJson(
          await _client.putJson('/service-now/profil', profile.toJson()));

  Future<PrestataireDisponibiliteDto> calendar() async =>
      PrestataireDisponibiliteDto.fromJson(
          await _client.getJson('/service-now/disponibilites'));

  Future<PrestataireDisponibiliteDto> saveCalendar(
    PrestataireDisponibiliteDto calendar,
  ) async =>
      PrestataireDisponibiliteDto.fromJson(await _client.putJson(
          '/service-now/disponibilites', calendar.toJson()));

  Future<List<ServiceNowMessageDto>> messages(int demandeId) async => _messages(
      await _client.getJson('/service-now/demandes/$demandeId/messages'));

  Future<List<ServiceNowMessageDto>> sendMessage(
    int demandeId,
    String contenu,
  ) async =>
      _messages(await _client.postJson(
          '/service-now/demandes/$demandeId/messages', {'contenu': contenu}));

  List<ServiceNowMessageDto> _messages(Map<String, dynamic> data) =>
      (data['items'] as List)
          .map((e) => ServiceNowMessageDto.fromJson(e as Map<String, dynamic>))
          .toList();

  /// New notifications; the server marks them as delivered.
  Future<List<ServiceNowNotificationDto>> takeNotifications() async {
    final data = await _client.postJson('/service-now/notifications/nouvelles');
    return (data['items'] as List)
        .map((e) =>
            ServiceNowNotificationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DemandeServiceDto> _post(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async =>
      DemandeServiceDto.fromJson(await _client.postJson(path, body));

  Future<List<DemandeServiceDto>> _list(String path) async {
    final data = await _client.getJson(path);
    return (data['items'] as List)
        .map((e) => DemandeServiceDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _utc(DateTime value) => value.toUtc().toIso8601String();
}
