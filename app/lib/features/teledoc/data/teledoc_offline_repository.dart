import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';
import '../domain/teledoc_history_store.dart';
import '../domain/teledoc_repository.dart';

/// [TeledocRepository] decorator: every call goes to the server; the
/// consultation history is also copied into a [TeledocHistoryStore] and read
/// back from it when the server cannot be reached (network error only, never
/// for a 4xx refusal). Writes always need the server.
class TeledocOfflineRepository
    implements TeledocRepository, TeledocOfflineAware {
  TeledocOfflineRepository(this._remote, this._history, this._userId);

  final TeledocRepository _remote;
  final TeledocHistoryStore _history;
  final int _userId;

  final ValueNotifier<bool> _cached = ValueNotifier(false);

  @override
  ValueListenable<bool> get servingCachedHistory => _cached;

  /// The local copy is a convenience: a disk error must never break the
  /// online path, so it is logged and ignored.
  Future<void> _keep(Future<void> Function() write) async {
    try {
      await write();
    } catch (e, s) {
      developer.log('Historique local non mis à jour',
          name: 'teledoc', error: e, stackTrace: s);
    }
  }

  Future<TeledocConsultationDto> _saved(
    Future<TeledocConsultationDto> call,
  ) async {
    final c = await call;
    _cached.value = false;
    await _keep(() => _history.save(_userId, c));
    return c;
  }

  /// Runs [remote]; on a network error answers with [local] when it has
  /// something, otherwise rethrows the original error.
  Future<T> _withFallback<T extends Object>(
    Future<T> Function() remote,
    Future<T?> Function() local,
  ) async {
    try {
      final value = await remote();
      _cached.value = false;
      return value;
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      T? copy;
      try {
        copy = await local();
      } catch (le, s) {
        developer.log('Historique local illisible',
            name: 'teledoc', error: le, stackTrace: s);
      }
      if (copy == null) rethrow;
      _cached.value = true;
      return copy;
    }
  }

  // ---- Consultations : copie locale ----

  @override
  Future<List<TeledocConsultationDto>> consultations() => _withFallback(
        () async {
          final list = await _remote.consultations();
          await _keep(() => _history.replaceAll(_userId, list));
          return list;
        },
        () async {
          final list = await _history.all(_userId);
          return list.isEmpty ? null : list;
        },
      );

  @override
  Future<TeledocConsultationDto> consultation(int id) => _withFallback(
        () => _saved(_remote.consultation(id)),
        () => _history.byId(_userId, id),
      );

  @override
  Future<TeledocConsultationDto> updateConsultation(
    int id, {
    TeledocConsultationType? type,
    String? ordonnance,
  }) =>
      _saved(_remote.updateConsultation(id, type: type, ordonnance: ordonnance));

  @override
  Future<TeledocConsultationDto> endConsultation(int id, String ordonnance) =>
      _saved(_remote.endConsultation(id, ordonnance));

  @override
  Future<TeledocConsultationDto> choosePharmacy(
    int consultationId,
    int pharmacyId,
  ) =>
      _saved(_remote.choosePharmacy(consultationId, pharmacyId));

  @override
  Future<void> deleteConsultation(int id) async {
    await _remote.deleteConsultation(id);
    await _keep(() => _history.delete(_userId, id));
  }

  @override
  Future<TeledocConsultationDto> startNextConsultation(
    TeledocConsultationType type,
  ) =>
      _saved(_remote.startNextConsultation(type));

  // ---- Le reste passe directement au serveur ----

  @override
  Future<List<TeledocRequestDto>> myRequests({TeledocRequestStatus? statut}) =>
      _remote.myRequests(statut: statut);

  @override
  Future<TeledocRequestDto> request(int id) => _remote.request(id);

  @override
  Future<TeledocRequestDto> createRequest({
    required String motif,
    required String description,
    required TeledocUrgency urgence,
    List<int>? photoBytes,
  }) =>
      _remote.createRequest(
        motif: motif,
        description: description,
        urgence: urgence,
        photoBytes: photoBytes,
      );

  @override
  Future<TeledocRequestDto> updateRequest(
    int id, {
    String? motif,
    String? description,
    TeledocUrgency? urgence,
    List<int>? photoBytes,
    bool removePhoto = false,
  }) =>
      _remote.updateRequest(
        id,
        motif: motif,
        description: description,
        urgence: urgence,
        photoBytes: photoBytes,
        removePhoto: removePhoto,
      );

  @override
  Future<TeledocRequestDto> cancelRequest(int id) => _remote.cancelRequest(id);

  @override
  Future<TeledocQueueStatusDto> queueStatus(int id) => _remote.queueStatus(id);

  @override
  TeledocPhotoSource photoOf(TeledocRequestDto request) =>
      _remote.photoOf(request);

  @override
  Future<List<TeledocRequestDto>> waitingQueue() => _remote.waitingQueue();

  @override
  Future<List<TeledocPharmacyDto>> nearestPharmacies({
    required double lat,
    required double lng,
    int limit = 10,
  }) =>
      _remote.nearestPharmacies(lat: lat, lng: lng, limit: limit);
}
