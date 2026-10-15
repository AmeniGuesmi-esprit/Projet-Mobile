import 'dart:math';

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../repositories/teledoc_consultation_repository.dart';
import '../repositories/teledoc_pharmacy_repository.dart';
import '../repositories/teledoc_request_repository.dart';
import 'teledoc_payment_gateway.dart';
import 'teledoc_photo_store.dart';
import 'teledoc_queue_service.dart';

/// The authenticated caller, as seen by TeleDoc: patients are `client`
/// accounts, doctors `medecin` accounts. Any other role is refused.
class TeledocUser {
  const TeledocUser(this.id, this.actor);

  factory TeledocUser.fromRole(int id, UserRole role) => switch (role) {
        UserRole.client => TeledocUser(id, TeledocActor.patient),
        UserRole.medecin => TeledocUser(id, TeledocActor.medecin),
        _ => throw ApiError.forbidden(
            'TeleDoc Express est réservé aux patients et aux médecins'),
      };

  final int id;
  final TeledocActor actor;

  bool get isPatient => actor == TeledocActor.patient;
  bool get isDoctor => actor == TeledocActor.medecin;
}

/// Business rules of TeleDoc Express: requests, consultations, pharmacies.
///
/// Access rules (CONCEPTION.md §6): a patient only sees their own requests
/// and consultations; a doctor sees the waiting queue and what they handle.
/// Resources the caller may not see answer 404, so their existence is not
/// revealed.
class TeledocService {
  TeledocService({
    required Database db,
    required this.requests,
    required this.consultations,
    required this.pharmacies,
    required this.photos,
    required this.payments,
    required this.queue,
    DateTime Function()? clock,
  })  : _db = db,
        _now = clock ?? DateTime.now;

  final Database _db;
  final TeledocRequestRepository requests;
  final TeledocConsultationRepository consultations;
  final TeledocPharmacyRepository pharmacies;
  final TeledocPhotoStore photos;
  final TeledocPaymentGateway payments;
  final TeledocQueueService queue;
  final DateTime Function() _now;

  String _timestamp() => _now().toIso8601String();

  // -------------------------------------------------------------------------
  // Demandes de consultation (patient)
  // -------------------------------------------------------------------------

  /// Creates a request, then charges it (use case "include : payer").
  /// The gateway is called outside any SQLite transaction: the Payment
  /// module opens its own, and nesting deadlocks sqflite.
  Future<TeledocRequestDto> createRequest(
    TeledocUser user, {
    required String? motif,
    required String? description,
    required String? urgence,
    String? photoBase64,
  }) async {
    _requirePatient(user);
    _check(teledocMotifError(motif));
    _check(teledocDescriptionError(description));
    final level = _parseUrgency(urgence);
    if (await requests.countActiveForPatient(user.id) > 0) {
      throw ApiError.conflict(
          'Vous avez déjà une demande en cours : attendez la fin de la '
          'consultation ou annulez-la');
    }

    final photo = (photoBase64 == null || photoBase64.trim().isEmpty)
        ? null
        : await photos.save(photoBase64);
    final at = _timestamp();
    final id = await requests.insert({
      'motif': motif!.trim(),
      'description': description!.trim(),
      'urgence': level.apiValue,
      'photo_symptome': photo,
      'statut': TeledocRequestStatus.enAttente.apiValue,
      'patient_id': user.id,
      'transaction_id': null,
      'cree_le': at,
      'modifie_le': at,
    });

    final int transactionId;
    try {
      transactionId = await payments.charge(
        patientId: user.id,
        amountCents: TeledocPricing.consultationCents,
        requestId: id,
      );
    } catch (e) {
      // Not paid → never queued.
      await requests.delete(id);
      await photos.delete(photo);
      if (e is TeledocPaymentDeclined) throw ApiError(402, e.message);
      rethrow;
    }
    await requests.update(id, {'transaction_id': transactionId});
    return getRequest(user, id);
  }

  Future<List<TeledocRequestDto>> listRequests(
    TeledocUser user, {
    TeledocRequestStatus? statut,
  }) async {
    _requirePatient(user);
    final rows = await requests.listForPatient(user.id, statut: statut);
    return _requestDtos(rows);
  }

  Future<TeledocRequestDto> getRequest(TeledocUser user, int id) async {
    final row = await _visibleRequest(user, id);
    return (await _requestDtos([row])).single;
  }

  Future<TeledocRequestDto> updateRequest(
    TeledocUser user,
    int id, {
    String? motif,
    String? description,
    String? urgence,
    String? photoBase64,
    bool removePhoto = false,
  }) async {
    _requirePatient(user);
    final row = await _visibleRequest(user, id);
    if (!TeledocRequestRules.canEdit(_status(row))) {
      throw ApiError.conflict(
          'Seule une demande en attente peut être modifiée');
    }

    final values = <String, Object?>{};
    if (motif != null) {
      _check(teledocMotifError(motif));
      values['motif'] = motif.trim();
    }
    if (description != null) {
      _check(teledocDescriptionError(description));
      values['description'] = description.trim();
    }
    if (urgence != null) {
      values['urgence'] = _parseUrgency(urgence).apiValue;
    }
    final oldPhoto = row['photo_symptome'] as String?;
    var replacesPhoto = false;
    if (photoBase64 != null && photoBase64.trim().isNotEmpty) {
      values['photo_symptome'] = await photos.save(photoBase64);
      replacesPhoto = true;
    } else if (removePhoto) {
      values['photo_symptome'] = null;
      replacesPhoto = true;
    }
    if (values.isEmpty) throw ApiError.badRequest('Aucune modification');

    values['modifie_le'] = _timestamp();
    await requests.update(id, values);
    // Remove the previous file only once the database points elsewhere.
    if (replacesPhoto) await photos.delete(oldPhoto);
    return getRequest(user, id);
  }

  /// Patient: cancels a waiting request. Doctor in charge: interrupts an
  /// ongoing consultation (patient absent). Paid requests are refunded.
  Future<TeledocRequestDto> cancelRequest(TeledocUser user, int id) async {
    final row = await _visibleRequest(user, id);
    final status = _status(row);
    if (user.isDoctor && row['c_medecin_id'] != user.id) {
      throw ApiError.notFound('Demande introuvable');
    }
    if (!TeledocRequestRules.canTransition(
        status, TeledocRequestStatus.annulee, user.actor)) {
      throw ApiError.conflict(switch ((user.actor, status)) {
        (TeledocActor.patient, TeledocRequestStatus.enCours) =>
          'La consultation a commencé : seul le médecin peut l\'interrompre',
        _ => 'Cette demande ne peut plus être annulée',
      });
    }

    // Refund first: if it is refused, the request stays as it was.
    final transactionId = row['transaction_id'] as int?;
    if (transactionId != null) {
      try {
        await payments.refund(
          transactionId: transactionId,
          patientId: row['patient_id'] as int,
        );
      } on TeledocPaymentDeclined catch (e) {
        throw ApiError.conflict('Remboursement impossible : ${e.message}');
      }
    }

    final at = _timestamp();
    await _db.transaction((txn) async {
      await requests.update(
          id,
          {
            'statut': TeledocRequestStatus.annulee.apiValue,
            'modifie_le': at,
          },
          txn);
      final consultationId = row['c_id'] as int?;
      if (consultationId != null) {
        // Closes the interrupted consultation (frees the doctor).
        await consultations.update(consultationId, {'date_fin': at}, txn);
      }
    });
    return getRequest(user, id);
  }

  Future<TeledocPhoto> requestPhoto(TeledocUser user, int id) async {
    final row = await _visibleRequest(user, id);
    final name = row['photo_symptome'] as String?;
    final photo = name == null ? null : await photos.read(name);
    if (photo == null) {
      throw ApiError.notFound('Aucune photo pour cette demande');
    }
    return photo;
  }

  // -------------------------------------------------------------------------
  // File d'attente virtuelle
  // -------------------------------------------------------------------------

  /// Patient: lightweight status polled by the waiting screen.
  Future<TeledocQueueStatusDto> queueStatus(TeledocUser user, int id) async {
    _requirePatient(user);
    final row = await _visibleRequest(user, id);
    final snapshot = await queue.snapshot();
    final place = snapshot.placeOf(id);
    final cType = row['c_type'] as String?;
    return TeledocQueueStatusDto(
      idDemande: id,
      statut: _status(row),
      positionFile: place?.position,
      tempsEstimeMinutes: place?.waitMinutes,
      taille: snapshot.size,
      consultationId: row['c_id'] as int?,
      typeConsultation:
          cType == null ? null : TeledocConsultationType.parse(cType),
      salleAppel: _status(row) == TeledocRequestStatus.enCours
          ? row['c_salle_appel'] as String?
          : null,
    );
  }

  /// Doctor: the waiting queue, head first, with positions and waits.
  Future<List<TeledocRequestDto>> waitingQueue(TeledocUser user) async {
    _requireDoctor(user);
    final snapshot = await queue.snapshot();
    return [
      for (final row in snapshot.ordered)
        requests.toDto(row, place: snapshot.placeOf(row['id'] as int)),
    ];
  }

  /// Doctor: starts a consultation with the request at the head of the
  /// queue (decision D4). Runs in one transaction so that two doctors can
  /// never take the same request; the partial unique index (D5) guarantees
  /// one open consultation per doctor even under concurrent calls.
  Future<TeledocConsultationDto> startNextConsultation(
    TeledocUser user, {
    required String? type,
  }) async {
    _requireDoctor(user);
    final callType = _parseType(type);
    final at = _timestamp();

    final int consultationId;
    try {
      consultationId = await _db.transaction((txn) async {
        if (await consultations.findOpenForDoctor(user.id, txn) != null) {
          throw ApiError.conflict(
              'Vous avez déjà une consultation en cours : terminez-la d\'abord');
        }
        final snapshot = await queue.snapshot(txn);
        if (snapshot.size == 0) {
          throw ApiError.notFound('Aucune demande en attente');
        }
        final head = snapshot.ordered.first;
        final requestId = head['id'] as int;
        if (!TeledocRequestRules.canTransition(
                _status(head), TeledocRequestStatus.enCours, user.actor) ||
            !await requests.claimWaiting(requestId, at, txn)) {
          throw ApiError.conflict(
              'Cette demande vient d\'être prise en charge, réessayez');
        }
        return consultations.insert({
          'date_debut': at,
          'date_fin': null,
          'type': callType.apiValue,
          'ordonnance': null,
          'pharmacie_id': null,
          'demande_id': requestId,
          'medecin_id': user.id,
          'salle_appel': newCallRoom(),
        }, txn);
      });
    } on DatabaseException catch (e) {
      // teledoc_consultation_une_en_cours / UNIQUE(demande_id).
      if (e.isUniqueConstraintError()) {
        throw ApiError.conflict('Consultation déjà en cours, réessayez');
      }
      rethrow;
    }
    return getConsultation(user, consultationId);
  }

  // -------------------------------------------------------------------------
  // Consultations
  // -------------------------------------------------------------------------

  Future<List<TeledocConsultationDto>> listConsultations(
      TeledocUser user) async {
    final rows = user.isDoctor
        ? await consultations.listForDoctor(user.id)
        : await consultations.listForPatient(user.id);
    return rows.map(consultations.toDto).toList();
  }

  Future<TeledocConsultationDto> getConsultation(
      TeledocUser user, int id) async {
    return consultations.toDto(await _visibleConsultation(user, id));
  }

  /// Doctor: changes the call type (only while in progress) and/or corrects
  /// the prescription (also after the end: CONCEPTION.md D10).
  Future<TeledocConsultationDto> updateConsultation(
    TeledocUser user,
    int id, {
    String? type,
    String? ordonnance,
  }) async {
    _requireDoctor(user);
    final row = await _visibleConsultation(user, id);
    final values = <String, Object?>{};
    if (type != null) {
      if (row['date_fin'] != null) {
        throw ApiError.conflict(
            'Le type d\'appel ne peut plus changer après la consultation');
      }
      values['type'] = _parseType(type).apiValue;
    }
    if (ordonnance != null) {
      _check(teledocOrdonnanceError(ordonnance));
      values['ordonnance'] = ordonnance.trim();
    }
    if (values.isEmpty) throw ApiError.badRequest('Aucune modification');
    await consultations.update(id, values);
    return getConsultation(user, id);
  }

  /// Doctor: ends the consultation; the prescription is mandatory
  /// (use case "include : rédiger l'ordonnance").
  Future<TeledocConsultationDto> endConsultation(
    TeledocUser user,
    int id, {
    required String? ordonnance,
  }) async {
    _requireDoctor(user);
    final row = await _visibleConsultation(user, id);
    if (row['date_fin'] != null) {
      throw ApiError.conflict('Cette consultation est déjà terminée');
    }
    _requireTransition(row, TeledocRequestStatus.terminee, user);
    _check(teledocOrdonnanceError(ordonnance));

    final at = _timestamp();
    await _db.transaction((txn) async {
      await consultations.update(
          id,
          {
            'date_fin': at,
            'ordonnance': ordonnance!.trim(),
          },
          txn);
      await requests.update(
          row['demande_id'] as int,
          {
            'statut': TeledocRequestStatus.terminee.apiValue,
            'modifie_le': at,
          },
          txn);
    });
    return getConsultation(user, id);
  }

  /// Doctor: deletes a consultation taken by mistake. The request goes back
  /// to the queue with its original date, hence its original rank. A
  /// finished consultation is a medical record and cannot be deleted (D10).
  Future<void> deleteConsultation(TeledocUser user, int id) async {
    _requireDoctor(user);
    final row = await _visibleConsultation(user, id);
    if (row['date_fin'] != null) {
      throw ApiError.conflict(
          'Une consultation terminée fait partie du dossier médical : '
          'elle peut être modifiée mais pas supprimée');
    }
    _requireTransition(row, TeledocRequestStatus.enAttente, user);

    await _db.transaction((txn) async {
      await consultations.delete(id, txn);
      await requests.update(
          row['demande_id'] as int,
          {
            'statut': TeledocRequestStatus.enAttente.apiValue,
            'modifie_le': _timestamp(),
          },
          txn);
    });
  }

  /// Patient: sends the prescription to a pharmacy (after the consultation).
  Future<TeledocConsultationDto> choosePharmacy(
    TeledocUser user,
    int id, {
    required int pharmacyId,
  }) async {
    _requirePatient(user);
    final row = await _visibleConsultation(user, id);
    if (_parseStatus(row['d_statut']) != TeledocRequestStatus.terminee) {
      throw ApiError.conflict(
          'L\'ordonnance n\'est disponible qu\'après la consultation');
    }
    if (await pharmacies.findById(pharmacyId) == null) {
      throw ApiError.notFound('Pharmacie introuvable');
    }
    await consultations.update(id, {'pharmacie_id': pharmacyId});
    return getConsultation(user, id);
  }

  // -------------------------------------------------------------------------
  // Pharmacies de garde
  // -------------------------------------------------------------------------

  /// On-duty pharmacies sorted by Haversine distance from ([lat], [lng]).
  Future<List<TeledocPharmacyDto>> nearestOnDutyPharmacies({
    required double lat,
    required double lng,
    int limit = 10,
  }) async {
    if (!GeoDistance.isValidLatitude(lat) ||
        !GeoDistance.isValidLongitude(lng)) {
      throw ApiError.badRequest('Coordonnées GPS invalides');
    }
    final rows = await pharmacies.listOnDuty();
    final withDistance = [
      for (final row in rows)
        (
          row: row,
          km: GeoDistance.haversineKm(
              lat,
              lng,
              (row['latitude'] as num).toDouble(),
              (row['longitude'] as num).toDouble()),
        ),
    ]..sort((a, b) => a.km.compareTo(b.km));
    return withDistance
        .take(limit.clamp(1, 50))
        .map((e) => pharmacies.toDto(e.row,
            distanceKm: double.parse(e.km.toStringAsFixed(2))))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// A fresh, unguessable Jitsi room (16 secure random bytes = 128 bits):
  /// the room name is the call's only access key (D35).
  static String newCallRoom() {
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${TeledocCallRoom.prefix}$hex';
  }

  /// Converts rows to DTOs, adding the derived queue position and wait to
  /// waiting requests (one snapshot for the whole list).
  Future<List<TeledocRequestDto>> _requestDtos(
      List<Map<String, Object?>> rows) async {
    final needsQueue =
        rows.any((r) => _status(r) == TeledocRequestStatus.enAttente);
    final snapshot = needsQueue ? await queue.snapshot() : null;
    return [
      for (final row in rows)
        requests.toDto(row, place: snapshot?.placeOf(row['id'] as int)),
    ];
  }

  /// Loads a request the caller is allowed to see, else 404.
  Future<Map<String, Object?>> _visibleRequest(TeledocUser user, int id) async {
    final row = await requests.findById(id);
    final visible = row != null &&
        (user.isPatient
            ? row['patient_id'] == user.id
            : _status(row) == TeledocRequestStatus.enAttente ||
                row['c_medecin_id'] == user.id);
    if (!visible) throw ApiError.notFound('Demande introuvable');
    return row;
  }

  Future<Map<String, Object?>> _visibleConsultation(
      TeledocUser user, int id) async {
    final row = await consultations.findById(id);
    final visible = row != null &&
        (user.isDoctor
            ? row['medecin_id'] == user.id
            : row['d_patient_id'] == user.id);
    if (!visible) throw ApiError.notFound('Consultation introuvable');
    return row;
  }

  void _requireTransition(Map<String, Object?> consultationRow,
      TeledocRequestStatus target, TeledocUser user) {
    final current = _parseStatus(consultationRow['d_statut']);
    if (!TeledocRequestRules.canTransition(current, target, user.actor)) {
      throw ApiError.conflict(
          'Action impossible : la demande est « ${current.label} »');
    }
  }

  void _requirePatient(TeledocUser user) {
    if (!user.isPatient) throw ApiError.forbidden('Réservé aux patients');
  }

  void _requireDoctor(TeledocUser user) {
    if (!user.isDoctor) throw ApiError.forbidden('Réservé aux médecins');
  }

  static void _check(String? error) {
    if (error != null) throw ApiError.badRequest(error);
  }

  static TeledocRequestStatus _status(Map<String, Object?> row) =>
      _parseStatus(row['statut']);

  static TeledocRequestStatus _parseStatus(Object? value) =>
      TeledocRequestStatus.parse(value as String);

  static TeledocUrgency _parseUrgency(String? value) {
    try {
      return TeledocUrgency.parse(value ?? '');
    } on ArgumentError {
      throw ApiError.badRequest('Urgence invalide : faible, moyenne ou elevee');
    }
  }

  static TeledocConsultationType _parseType(String? value) {
    try {
      return TeledocConsultationType.parse(value ?? '');
    } on ArgumentError {
      throw ApiError.badRequest('Type d\'appel invalide : audio ou video');
    }
  }
}
