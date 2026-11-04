import 'dart:convert';

import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';
import '../domain/teledoc_repository.dart';

/// [TeledocRepository] over the shared JSON [ApiClient] (not modified).
/// Photos travel as base64 inside the JSON body (CONCEPTION.md, D6).
class TeledocApiRepository implements TeledocRepository {
  TeledocApiRepository(this._client);

  final ApiClient _client;

  static List<T> _items<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson,
  ) => (data['items'] as List)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();

  // ---- Demandes ----

  @override
  Future<List<TeledocRequestDto>> myRequests({
    TeledocRequestStatus? statut,
  }) async {
    final query = statut == null ? '' : '?statut=${statut.apiValue}';
    return _items(
      await _client.getJson('/teledoc/requests$query'),
      TeledocRequestDto.fromJson,
    );
  }

  @override
  Future<TeledocRequestDto> request(int id) async => TeledocRequestDto.fromJson(
    await _client.getJson('/teledoc/requests/$id'),
  );

  @override
  Future<TeledocRequestDto> createRequest({
    required String motif,
    required String description,
    required TeledocUrgency urgence,
    List<int>? photoBytes,
  }) async {
    final data = await _client.postJson('/teledoc/requests', {
      'motif': motif,
      'description': description,
      'urgence': urgence.apiValue,
      if (photoBytes != null) 'photo_base64': base64Encode(photoBytes),
    });
    return TeledocRequestDto.fromJson(data);
  }

  @override
  Future<TeledocRequestDto> updateRequest(
    int id, {
    String? motif,
    String? description,
    TeledocUrgency? urgence,
    List<int>? photoBytes,
    bool removePhoto = false,
  }) async {
    final data = await _client.patchJson('/teledoc/requests/$id', {
      'motif': ?motif,
      'description': ?description,
      'urgence': ?urgence?.apiValue,
      if (photoBytes != null) 'photo_base64': base64Encode(photoBytes),
      if (removePhoto) 'supprimer_photo': true,
    });
    return TeledocRequestDto.fromJson(data);
  }

  @override
  Future<TeledocRequestDto> cancelRequest(int id) async =>
      TeledocRequestDto.fromJson(
        await _client.postJson('/teledoc/requests/$id/cancel'),
      );

  @override
  Future<TeledocQueueStatusDto> queueStatus(int id) async =>
      TeledocQueueStatusDto.fromJson(
        await _client.getJson('/teledoc/requests/$id/queue-status'),
      );

  /// The `v` parameter (ignored by the server) changes when the request is
  /// modified, so a replaced photo is not served from the image cache.
  @override
  TeledocPhotoSource photoOf(TeledocRequestDto request) => TeledocPhotoSource(
    '${_client.baseUrl}/teledoc/requests/${request.id}/photo'
    '?v=${Uri.encodeQueryComponent(request.modifieLe)}',
    {if (_client.token != null) 'authorization': 'Bearer ${_client.token}'},
  );

  // ---- File et consultations ----

  @override
  Future<List<TeledocRequestDto>> waitingQueue() async => _items(
    await _client.getJson('/teledoc/queue'),
    TeledocRequestDto.fromJson,
  );

  @override
  Future<TeledocConsultationDto> startNextConsultation(
    TeledocConsultationType type,
  ) async => TeledocConsultationDto.fromJson(
    await _client.postJson('/teledoc/consultations', {'type': type.apiValue}),
  );

  @override
  Future<List<TeledocConsultationDto>> consultations() async => _items(
    await _client.getJson('/teledoc/consultations'),
    TeledocConsultationDto.fromJson,
  );

  @override
  Future<TeledocConsultationDto> consultation(int id) async =>
      TeledocConsultationDto.fromJson(
        await _client.getJson('/teledoc/consultations/$id'),
      );

  @override
  Future<TeledocConsultationDto> updateConsultation(
    int id, {
    TeledocConsultationType? type,
    String? ordonnance,
  }) async => TeledocConsultationDto.fromJson(
    await _client.patchJson('/teledoc/consultations/$id', {
      'type': ?type?.apiValue,
      'ordonnance': ?ordonnance,
    }),
  );

  @override
  Future<TeledocConsultationDto> endConsultation(
    int id,
    String ordonnance,
  ) async => TeledocConsultationDto.fromJson(
    await _client.postJson('/teledoc/consultations/$id/end', {
      'ordonnance': ordonnance,
    }),
  );

  @override
  Future<void> deleteConsultation(int id) =>
      _client.deleteJson('/teledoc/consultations/$id');

  @override
  Future<TeledocConsultationDto> choosePharmacy(
    int consultationId,
    int pharmacyId,
  ) async => TeledocConsultationDto.fromJson(
    await _client.patchJson('/teledoc/consultations/$consultationId/pharmacy', {
      'id_pharmacie': pharmacyId,
    }),
  );

  // ---- Pharmacies ----

  @override
  Future<List<TeledocPharmacyDto>> nearestPharmacies({
    required double lat,
    required double lng,
    int limit = 10,
  }) async => _items(
    await _client.getJson(
      '/teledoc/pharmacies/on-duty?lat=$lat&lng=$lng&limit=$limit',
    ),
    TeledocPharmacyDto.fromJson,
  );
}
