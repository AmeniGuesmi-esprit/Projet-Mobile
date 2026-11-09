import 'dart:developer' as developer;
import 'dart:math';

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../foodsave/services/route_planner.dart';
import '../repositories/service_now_repository.dart';
import 'payment_service.dart';
import 'service_now_geocoder.dart';
import 'teledoc_photo_store.dart';

/// Business rules of ServiceNow: clients create demandes, prestataires take
/// them and carry out the interventions, clients pay when the work is done.
class ServiceNowService {
  ServiceNowService({
    required Database db,
    required ServiceNowRepository repository,
    required PaymentService payments,
    required AddressGeocoder geocoder,
    required RoutePlanner routes,
    required TeledocPhotoStore photos,
    DateTime Function()? clock,
  })  : _db = db,
        _repository = repository,
        _payments = payments,
        _geocoder = geocoder,
        _routes = routes,
        _photos = photos,
        _clock = clock ?? DateTime.now;

  final Database _db;
  final ServiceNowRepository _repository;
  final PaymentService _payments;
  final AddressGeocoder _geocoder;
  final RoutePlanner _routes;
  final TeledocPhotoStore _photos;
  final DateTime Function() _clock;

  /// No ambiguous characters (0/O, 1/I): the code can be typed by hand.
  static const String _qrAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Speed used for the arrival time when the routing service is down.
  static const double _fallbackSpeedKmh = 30;

  /// Everything that clears a live position.
  static const Map<String, Object?> _noPosition = {
    'prestataire_lat': null,
    'prestataire_lng': null,
    'position_le': null,
  };

  /// Interventions being paid right now. The server is a single isolate, so
  /// this stops a double tap from charging the client twice.
  final Set<int> _paying = {};

  // ------------------------------------------------------------ demandes --

  Future<DemandeServiceDto> createDemande(
    int userId,
    UserRole role, {
    required ServiceNowType type,
    required String description,
    required String adresse,
    required DateTime dateSouhaitee,
    ({double latitude, double longitude})? position,
  }) async {
    if (role == UserRole.prestataire) {
      throw ApiError.forbidden(
          'Un compte prestataire ne peut pas créer de demande');
    }
    final now = _clock();
    _validateDemande(description, adresse, dateSouhaitee, now);
    final id = await _repository.insertDemande(
      clientId: userId,
      type: type,
      description: description.trim(),
      adresse: adresse.trim(),
      dateSouhaitee: dateSouhaitee,
      now: now,
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
    await _notifySpecialists(id, type, adresse.trim());
    return _reload(id, userId, role);
  }

  Future<DemandeServiceDto> updateDemande(
    int userId,
    UserRole role,
    int id, {
    ServiceNowType? type,
    String? description,
    String? adresse,
    DateTime? dateSouhaitee,
    bool updatePosition = false,
    ({double latitude, double longitude})? position,
  }) async {
    final row = await _requireDemande(id);
    if (row['client_id'] != userId) {
      throw ApiError.forbidden('Cette demande ne vous appartient pas');
    }
    if (!ServiceNowRules.clientCanEdit(_demandeStatus(row))) {
      throw ApiError.conflict(
          'Cette demande ne peut plus être modifiée : un prestataire l\'a prise en charge');
    }
    final newType = type ?? ServiceNowType.parse(row['type'] as String);
    final newDescription = description ?? row['description'] as String;
    final newAdresse = adresse ?? row['adresse'] as String;
    final newDate =
        dateSouhaitee ?? DateTime.parse(row['date_souhaitee'] as String);
    final now = _clock();
    _validateDemande(newDescription, newAdresse, newDate, now);
    final updated = await _repository.updateOpenDemande(
      id,
      type: newType,
      description: newDescription.trim(),
      adresse: newAdresse.trim(),
      dateSouhaitee: newDate,
      now: now,
      latitude: updatePosition ? position?.latitude : _double(row['latitude']),
      longitude:
          updatePosition ? position?.longitude : _double(row['longitude']),
    );
    if (!updated) {
      throw ApiError.conflict(
          'Cette demande ne peut plus être modifiée : un prestataire l\'a prise en charge');
    }
    return _reload(id, userId, role);
  }

  Future<DemandeServiceDto> cancelDemande(
    int userId,
    UserRole role,
    int id,
  ) async {
    final row = await _requireDemande(id);
    final isAdmin = role == UserRole.admin;
    if (row['client_id'] != userId && !isAdmin) {
      throw ApiError.forbidden('Cette demande ne vous appartient pas');
    }
    final status = _demandeStatus(row);
    final allowed = isAdmin
        ? ServiceNowRules.canMoveDemande(status, DemandeServiceStatus.annulee)
        : ServiceNowRules.clientCanCancel(status);
    if (!allowed) {
      throw ApiError.conflict('Cette demande ne peut plus être annulée');
    }
    final now = _clock();
    var wasLive = false;
    await _db.transaction((txn) async {
      final moved = await _repository.moveDemande(
        txn,
        id,
        from: status,
        to: DemandeServiceStatus.annulee,
        now: now,
      );
      if (!moved) {
        throw ApiError.conflict('Cette demande vient de changer de statut');
      }
      wasLive = row['i_id'] != null &&
          ServiceNowRules.canMoveIntervention(
            _interventionStatus(row),
            InterventionStatus.annulee,
          );
      final interventionId = row['i_id'] as int?;
      if (interventionId == null) return;
      final interventionStatus = _interventionStatus(row);
      if (ServiceNowRules.canMoveIntervention(
          interventionStatus, InterventionStatus.annulee)) {
        await _repository.moveIntervention(
          txn,
          interventionId,
          from: interventionStatus,
          to: InterventionStatus.annulee,
          now: now,
          values: _noPosition,
        );
      }
    });
    if (wasLive) {
      await _notify(row['i_prestataire_id'] as int?, id, 'Demande annulée',
          'Le client a annulé cette intervention.');
    }
    if (isAdmin && row['client_id'] != userId) {
      await _notify(row['client_id'] as int?, id, 'Demande annulée',
          'Votre demande a été annulée par ProxiLife.');
    }
    return _reload(id, userId, role);
  }

  Future<DemandeServiceDto> getDemande(
    int userId,
    UserRole role,
    int id,
  ) async {
    final row = await _requireDemande(id);
    final canSee = row['client_id'] == userId ||
        role == UserRole.admin ||
        row['i_prestataire_id'] == userId ||
        (role == UserRole.prestataire &&
            _demandeStatus(row) == DemandeServiceStatus.enAttente);
    if (!canSee) throw ApiError.forbidden('Accès refusé à cette demande');
    return _toDto(row, userId, role);
  }

  Future<List<DemandeServiceDto>> listMine(int userId, UserRole role) async {
    final rows = await _repository.listForClient(userId);
    return [for (final row in rows) _toDto(row, userId, role)];
  }

  Future<List<DemandeServiceDto>> listOpen(
    int userId,
    UserRole role, {
    ServiceNowType? type,
  }) async {
    if (role != UserRole.prestataire && role != UserRole.admin) {
      throw ApiError.forbidden('Réservé aux prestataires');
    }
    final profile = await _repository.findProfile(userId);
    final specialties = _specialties(profile?['specialites']);
    final agenda = _agendaOf(await _loadAgendas(), userId);
    final rows = await _repository.listOpen(type: type);
    final ranked = [
      for (final row in rows) _rank(row, profile, specialties, agenda),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return [
      for (final entry in ranked)
        _toDto(
          entry.row,
          userId,
          role,
          distanceKm: entry.distanceKm,
          specialtyMatch: entry.specialty,
          availableOnDate: entry.available,
        ),
    ];
  }

  /// Smart matching: scores a waiting request for one prestataire.
  ({
    Map<String, Object?> row,
    double? distanceKm,
    bool specialty,
    bool available,
    double score,
  }) _rank(
    Map<String, Object?> row,
    Map<String, Object?>? profile,
    Set<ServiceNowType> specialties,
    _Agenda agenda,
  ) {
    final distanceKm = _distance(
      profile?['latitude'],
      profile?['longitude'],
      row['latitude'],
      row['longitude'],
    );
    final specialty =
        specialties.contains(ServiceNowType.parse(row['type'] as String));
    final available = agenda
        .isFreeAt(DateTime.parse(row['date_souhaitee'] as String).toLocal());
    final score = ServiceNowRules.matchScore(
      distanceKm: distanceKm,
      specialty: specialty,
      rating: null,
    );
    return (
      row: row,
      distanceKm: distanceKm,
      specialty: specialty,
      available: available,
      // Still listed, but after the requests he can actually take.
      score: available ? score : score / 2,
    );
  }

  /// Smart matching, client side: the 5 best prestataires for a request,
  /// using distance, specialty and rating.
  Future<List<NearbyPrestataireDto>> nearbyPrestataires(
    int userId,
    UserRole role,
    int demandeId,
  ) async {
    final row = await _requireDemande(demandeId);
    if (row['client_id'] != userId && role != UserRole.admin) {
      throw ApiError.forbidden('Cette demande ne vous appartient pas');
    }
    final type = ServiceNowType.parse(row['type'] as String);
    final when = DateTime.parse(row['date_souhaitee'] as String).toLocal();
    final agendas = await _loadAgendas();
    final ranked = [
      for (final candidate in await _repository.listPrestataires())
        // Smart matching skips anyone who is not free at the wanted time.
        if (_agendaOf(agendas, candidate['id'] as int).isFreeAt(when))
          _rankPrestataire(candidate, row, type),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return [for (final entry in ranked.take(5)) entry.dto];
  }

  ({NearbyPrestataireDto dto, double score}) _rankPrestataire(
    Map<String, Object?> candidate,
    Map<String, Object?> demande,
    ServiceNowType type,
  ) {
    final distanceKm = _distance(
      candidate['latitude'],
      candidate['longitude'],
      demande['latitude'],
      demande['longitude'],
    );
    final specialist = _specialties(candidate['specialites']).contains(type);
    final rating = _double(candidate['note_moyenne']);
    return (
      dto: NearbyPrestataireDto(
        id: candidate['id'] as int,
        nom: _displayName(
          candidate['prenom'] as String,
          candidate['nom'] as String,
          full: false,
        ),
        specialiste: specialist,
        nbNotes: candidate['nb_notes'] as int,
        distanceKm: distanceKm,
        noteMoyenne: rating,
      ),
      score: ServiceNowRules.matchScore(
        distanceKm: distanceKm,
        specialty: specialist,
        rating: rating,
      ),
    );
  }

  Future<PriceEstimateDto> estimatePrice(ServiceNowType type) async {
    final (low, high, count) = ServiceNowRules.estimatePrice(
      type,
      await _repository.pastPrices(type),
    );
    return PriceEstimateDto(
      minCentimes: low,
      maxCentimes: high,
      basedOn: count,
    );
  }

  Future<List<GeocodeResultDto>> searchAddress(String query) async {
    if (query.trim().length < 3) {
      throw ApiError.badRequest('Saisissez une adresse plus précise');
    }
    final results = await _geocoder.search(query.trim());
    if (results == null) {
      throw const ApiError(503, 'Recherche d\'adresse indisponible, réessayez');
    }
    return results;
  }

  // -------------------------------------------------- prestataire profile --

  Future<PrestataireProfilDto> getProfile(int userId, UserRole role) async {
    _requirePrestataire(role);
    final profile = await _repository.findProfile(userId);
    return PrestataireProfilDto(
      specialites: _specialties(profile?['specialites']),
      latitude: _double(profile?['latitude']),
      longitude: _double(profile?['longitude']),
    );
  }

  Future<PrestataireProfilDto> saveProfile(
    int userId,
    UserRole role, {
    required Set<ServiceNowType> specialites,
    ({double latitude, double longitude})? position,
  }) async {
    _requirePrestataire(role);
    await _repository.saveProfile(
      userId,
      specialites: specialites.map((type) => type.apiValue).join(','),
      latitude: position?.latitude,
      longitude: position?.longitude,
      now: _clock(),
    );
    return getProfile(userId, role);
  }

  // -------------------------------------------------------- interventions --

  Future<List<DemandeServiceDto>> listMyInterventions(
    int userId,
    UserRole role,
  ) async {
    _requirePrestataire(role);
    final rows = await _repository.listForPrestataire(userId);
    return [for (final row in rows) _toDto(row, userId, role)];
  }

  /// The prestataire takes a waiting request: creates the intervention.
  Future<DemandeServiceDto> acceptDemande(
    int userId,
    UserRole role,
    int demandeId, {
    required DateTime datePrevue,
    required int prixCentimes,
  }) async {
    _requirePrestataire(role);
    final demande = await _requireDemande(demandeId);
    final now = _clock();
    _throwIfError(ServiceNowRules.scheduleError(datePrevue, now: now));
    _throwIfError(ServiceNowRules.priceError(prixCentimes));
    final agenda = _agendaOf(await _loadAgendas(), userId);
    if (!agenda.isFreeAt(datePrevue.toLocal())) {
      throw ApiError.conflict(
          'Vous n\'êtes pas disponible à cette date : choisissez un autre créneau');
    }
    await _db.transaction((txn) async {
      // Only one prestataire can win: the status check is part of the UPDATE.
      final moved = await _repository.moveDemande(
        txn,
        demandeId,
        from: DemandeServiceStatus.enAttente,
        to: DemandeServiceStatus.acceptee,
        now: now,
      );
      if (!moved) {
        throw ApiError.conflict('Cette demande n\'est plus disponible');
      }
      await _repository.insertIntervention(
        txn,
        demandeId: demandeId,
        prestataireId: userId,
        datePrevue: datePrevue,
        prixCentimes: prixCentimes,
        qrCode: _newQrCode(),
        now: now,
      );
    });
    await _notify(demande['client_id'] as int?, demandeId, 'Demande acceptée',
        'Un prestataire a accepté votre demande.');
    return _reload(demandeId, userId, role);
  }

  Future<DemandeServiceDto> startIntervention(
    int userId,
    UserRole role,
    int interventionId, {
    required String? qrCode,
  }) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    // Proof of presence: the code is only visible on the client's phone.
    final expected = row['i_qr_code'] as String?;
    if (expected != null && qrCode?.trim().toUpperCase() != expected) {
      throw ApiError.badRequest('Code de présence invalide');
    }
    final demandeId = row['id'] as int;
    final now = _clock();
    await _move(
      interventionId,
      demandeId,
      fromIntervention: InterventionStatus.planifiee,
      toIntervention: InterventionStatus.enCours,
      fromDemande: DemandeServiceStatus.acceptee,
      toDemande: DemandeServiceStatus.enCours,
      now: now,
      values: {'date_debut': now.toUtc().toIso8601String(), ..._noPosition},
      conflictMessage: 'Cette intervention ne peut pas être démarrée',
    );
    await _notify(row['client_id'] as int?, demandeId, 'Intervention démarrée',
        'Le prestataire a commencé le travail.');
    return _reload(demandeId, userId, role);
  }

  /// [prixCentimes] replaces the agreed price when the final bill differs.
  Future<DemandeServiceDto> finishIntervention(
    int userId,
    UserRole role,
    int interventionId, {
    required String rapport,
    int? prixCentimes,
  }) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    _throwIfError(ServiceNowRules.reportError(rapport));
    final prix = prixCentimes ?? row['i_prix_centimes'] as int;
    _throwIfError(ServiceNowRules.priceError(prix));
    final demandeId = row['id'] as int;
    final now = _clock();
    await _move(
      interventionId,
      demandeId,
      fromIntervention: InterventionStatus.enCours,
      toIntervention: InterventionStatus.terminee,
      fromDemande: DemandeServiceStatus.enCours,
      toDemande: DemandeServiceStatus.terminee,
      now: now,
      values: {
        'date_fin': now.toUtc().toIso8601String(),
        'rapport': rapport.trim(),
        'prix_centimes': prix,
      },
      conflictMessage: 'Cette intervention ne peut pas être terminée',
    );
    await _notify(row['client_id'] as int?, demandeId, 'Intervention terminée',
        'Le travail est terminé : vous pouvez régler et noter le prestataire.');
    return _reload(demandeId, userId, role);
  }

  /// Before starting, the prestataire can withdraw: the request goes back
  /// to the list of waiting requests.
  Future<DemandeServiceDto> withdraw(
    int userId,
    UserRole role,
    int interventionId,
  ) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    final demandeId = row['id'] as int;
    await _move(
      interventionId,
      demandeId,
      fromIntervention: InterventionStatus.planifiee,
      toIntervention: InterventionStatus.annulee,
      fromDemande: DemandeServiceStatus.acceptee,
      toDemande: DemandeServiceStatus.enAttente,
      now: _clock(),
      values: _noPosition,
      conflictMessage: 'Vous ne pouvez plus vous désister de cette intervention',
    );
    await _notify(row['client_id'] as int?, demandeId, 'Prestataire désisté',
        'Votre demande est de nouveau proposée aux prestataires.');
    return _reload(demandeId, userId, role);
  }

  /// The client pays the prestataire through the Payment module.
  Future<DemandeServiceDto> payIntervention(
    int userId,
    UserRole role,
    int interventionId, {
    int? moyenPaiementId,
  }) async {
    if (!_paying.add(interventionId)) {
      throw ApiError.conflict('Un paiement est déjà en cours');
    }
    try {
      final row = await _requireIntervention(interventionId);
      if (row['client_id'] != userId) {
        throw ApiError.forbidden('Cette intervention ne vous appartient pas');
      }
      final payment = row['t_statut'] == null
          ? null
          : TransactionStatus.parse(row['t_statut'] as String);
      if (!ServiceNowRules.canPay(_interventionStatus(row), payment)) {
        throw ApiError.conflict('Cette intervention ne peut pas être payée');
      }
      final email = row['p_email'] as String?;
      if (email == null) {
        throw ApiError.conflict('Ce prestataire n\'est plus inscrit');
      }
      final transaction = await _payments.createTransaction(
        userId,
        montantCentimes: row['i_prix_centimes'] as int,
        beneficiaireEmail: email,
        typeService: ServiceType.serviceNow,
        idReference: 'SN-$interventionId',
        moyenPaiementId: moyenPaiementId,
      );
      if (transaction.statut == TransactionStatus.echoue) {
        throw const ApiError(402,
            'Solde insuffisant : rechargez votre portefeuille ou payez par carte');
      }
      await _repository.setTransaction(
        interventionId,
        transaction.id,
        now: _clock(),
      );
      await _notify(
        row['i_prestataire_id'] as int?,
        row['id'] as int,
        'Paiement reçu',
        'Le client a réglé votre intervention.',
      );
      return _reload(row['id'] as int, userId, role);
    } finally {
      _paying.remove(interventionId);
    }
  }

  /// The client rates the prestataire, once, after paying.
  Future<DemandeServiceDto> rateIntervention(
    int userId,
    UserRole role,
    int interventionId, {
    required int note,
    String? commentaire,
  }) async {
    final row = await _requireIntervention(interventionId);
    if (row['client_id'] != userId) {
      throw ApiError.forbidden('Cette intervention ne vous appartient pas');
    }
    _throwIfError(ServiceNowRules.ratingError(note));
    _throwIfError(ServiceNowRules.commentError(commentaire ?? ''));
    final payment = row['t_statut'] == null
        ? null
        : TransactionStatus.parse(row['t_statut'] as String);
    if (!ServiceNowRules.canRate(
      _interventionStatus(row),
      payment,
      alreadyRated: row['i_note'] != null,
    )) {
      throw ApiError.conflict('Cette intervention ne peut pas être notée');
    }
    final trimmed = commentaire?.trim();
    final saved = await _repository.rateOnce(
      interventionId,
      note: note,
      commentaire: trimmed == null || trimmed.isEmpty ? null : trimmed,
      now: _clock(),
    );
    if (!saved) throw ApiError.conflict('Vous avez déjà noté cette intervention');
    await _notify(row['i_prestataire_id'] as int?, row['id'] as int,
        'Nouvelle note', 'Un client vous a donné $note/5.');
    return _reload(row['id'] as int, userId, role);
  }

  /// Before/after photo, added while the work is in progress.
  Future<DemandeServiceDto> addPhoto(
    int userId,
    UserRole role,
    int interventionId, {
    required InterventionPhotoKind kind,
    required String base64Data,
  }) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    if (_interventionStatus(row) != InterventionStatus.enCours) {
      throw ApiError.conflict('Les photos s\'ajoutent pendant l\'intervention');
    }
    final name = await _photos.save(base64Data);
    await _repository.updateIntervention(
      interventionId,
      {_photoColumn(kind): name},
      now: _clock(),
    );
    await _photos.delete(row['i_${_photoColumn(kind)}'] as String?);
    return _reload(row['id'] as int, userId, role);
  }

  Future<TeledocPhoto> readPhoto(
    int userId,
    UserRole role,
    int interventionId,
    InterventionPhotoKind kind,
  ) async {
    final row = await _requireIntervention(interventionId);
    _requireParticipant(row, userId, role);
    final name = row['i_${_photoColumn(kind)}'] as String?;
    final photo = name == null ? null : await _photos.read(name);
    if (photo == null) throw ApiError.notFound('Photo introuvable');
    return photo;
  }

  /// The prestataire leaves: live tracking starts.
  Future<DemandeServiceDto> startTrip(
    int userId,
    UserRole role,
    int interventionId, {
    required ({double latitude, double longitude}) position,
  }) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    if (_interventionStatus(row) != InterventionStatus.planifiee) {
      throw ApiError.conflict('Cette intervention a déjà commencé');
    }
    final now = _clock();
    await _repository.updateIntervention(
      interventionId,
      {
        'en_route_le': now.toUtc().toIso8601String(),
        ..._positionValues(position, now),
      },
      now: now,
    );
    await _notify(row['client_id'] as int?, row['id'] as int,
        'Prestataire en route', 'Suivez son arrivée sur la carte.');
    return _reload(row['id'] as int, userId, role);
  }

  Future<void> updatePosition(
    int userId,
    UserRole role,
    int interventionId, {
    required ({double latitude, double longitude}) position,
  }) async {
    final row = await _requireOwnIntervention(userId, role, interventionId);
    if (!_isTracking(row)) {
      throw ApiError.conflict('Le suivi de cette intervention est terminé');
    }
    final now = _clock();
    await _repository.updateIntervention(
      interventionId,
      _positionValues(position, now),
      now: now,
    );
  }

  /// Position and road to the client. If the routing service fails, falls
  /// back to a straight line so that tracking keeps working.
  Future<ServiceTrackingDto> tracking(
    int userId,
    UserRole role,
    int interventionId,
  ) async {
    final row = await _requireIntervention(interventionId);
    _requireParticipant(row, userId, role);
    final toLat = _double(row['latitude']);
    final toLng = _double(row['longitude']);
    final fromLat = _double(row['i_prestataire_lat']);
    final fromLng = _double(row['i_prestataire_lng']);
    if (!_isTracking(row) || fromLat == null || fromLng == null) {
      return ServiceTrackingDto(
        enRoute: false,
        approximatif: false,
        destinationLatitude: toLat,
        destinationLongitude: toLng,
      );
    }
    final positionLe = _date(row['i_position_le']);
    if (toLat == null || toLng == null) {
      return ServiceTrackingDto(
        enRoute: true,
        approximatif: false,
        latitude: fromLat,
        longitude: fromLng,
        positionLe: positionLe,
      );
    }
    final route = await _routes.route(
      fromLatitude: fromLat,
      fromLongitude: fromLng,
      toLatitude: toLat,
      toLongitude: toLng,
      mode: TravelMode.voiture,
    );
    final straightKm = GeoDistance.haversineKm(fromLat, fromLng, toLat, toLng);
    return ServiceTrackingDto(
      enRoute: true,
      approximatif: route == null,
      latitude: fromLat,
      longitude: fromLng,
      positionLe: positionLe,
      destinationLatitude: toLat,
      destinationLongitude: toLng,
      points: route?.points ?? [(fromLat, fromLng), (toLat, toLng)],
      distanceMetres: route?.distanceMetres ?? (straightKm * 1000).round(),
      dureeSecondes: route?.dureeSecondes ??
          (straightKm / _fallbackSpeedKmh * 3600).round(),
    );
  }

  // ------------------------------------------------- calendar and messages --

  Future<PrestataireDisponibiliteDto> getCalendar(
    int userId,
    UserRole role,
  ) async {
    _requirePrestataire(role);
    final agenda = _agendaOf(await _loadAgendas(), userId);
    return PrestataireDisponibiliteDto(
      creneaux: agenda.slots,
      joursOff: agenda.joursOff.toList()..sort(),
    );
  }

  Future<PrestataireDisponibiliteDto> saveCalendar(
    int userId,
    UserRole role, {
    required List<DisponibiliteSlotDto> creneaux,
    required Set<String> joursOff,
  }) async {
    _requirePrestataire(role);
    for (final slot in creneaux) {
      _throwIfError(ServiceNowRules.slotError(slot));
    }
    for (final day in joursOff) {
      _throwIfError(ServiceNowRules.dayOffError(day));
    }
    if (creneaux.map((slot) => slot.jour).toSet().length != creneaux.length) {
      throw ApiError.badRequest('Un seul créneau par jour');
    }
    await _repository.saveCalendar(userId, slots: creneaux, daysOff: joursOff);
    return getCalendar(userId, role);
  }

  Future<List<ServiceNowMessageDto>> listMessages(
    int userId,
    int demandeId,
  ) async {
    _requireChatParticipant(await _requireDemande(demandeId), userId);
    return [
      for (final row in await _repository.listMessages(demandeId))
        ServiceNowMessageDto(
          id: row['id'] as int,
          demandeId: row['demande_id'] as int,
          auteurId: row['auteur_id'] as int?,
          auteurNom: row['auteur_prenom'] as String? ?? 'Utilisateur',
          contenu: row['contenu'] as String,
          creeLe: DateTime.parse(row['cree_le'] as String),
        ),
    ];
  }

  Future<List<ServiceNowMessageDto>> sendMessage(
    int userId,
    int demandeId, {
    required String contenu,
  }) async {
    final row = await _requireDemande(demandeId);
    _requireChatParticipant(row, userId);
    _throwIfError(ServiceNowRules.messageError(contenu));
    if (!ServiceNowRules.canChat(_demandeStatus(row))) {
      throw ApiError.conflict('Cette conversation est fermée');
    }
    final text = contenu.trim();
    await _repository.insertMessage(
      demandeId: demandeId,
      auteurId: userId,
      contenu: text,
      now: _clock(),
    );
    final recipient = row['client_id'] == userId
        ? row['i_prestataire_id'] as int?
        : row['client_id'] as int?;
    await _notify(
      recipient,
      demandeId,
      'Nouveau message',
      text.length > 80 ? '${text.substring(0, 80)}…' : text,
    );
    return listMessages(userId, demandeId);
  }

  /// Notifications not yet shown on this user's phone.
  Future<List<ServiceNowNotificationDto>> takeNotifications(int userId) async {
    final rows = await _repository.takeNotifications(userId);
    return [
      for (final row in rows)
        ServiceNowNotificationDto(
          id: row['id'] as int,
          demandeId: row['demande_id'] as int,
          titre: row['titre'] as String,
          message: row['message'] as String,
        ),
    ];
  }

  // -------------------------------------------------------------- helpers --

  /// Everyone's calendar and live interventions. Hours and days off are read
  /// in the server's local time, the time zone the prestataires work in.
  Future<Map<int, _Agenda>> _loadAgendas() async {
    final agendas = <int, _Agenda>{};
    for (final row in await _repository.allSlots()) {
      agendas.putIfAbsent(row['utilisateur_id'] as int, _Agenda.new).slots.add(
            DisponibiliteSlotDto(
              jour: row['jour'] as int,
              debutMinutes: row['debut_minutes'] as int,
              finMinutes: row['fin_minutes'] as int,
            ),
          );
    }
    for (final row in await _repository.allDaysOff()) {
      agendas
          .putIfAbsent(row['utilisateur_id'] as int, _Agenda.new)
          .joursOff
          .add(row['jour'] as String);
    }
    for (final row in await _repository.liveInterventionDates()) {
      agendas
          .putIfAbsent(row['prestataire_id'] as int, _Agenda.new)
          .busy
          .add(DateTime.parse(row['date_prevue'] as String));
    }
    return agendas;
  }

  _Agenda _agendaOf(Map<int, _Agenda> agendas, int userId) =>
      agendas[userId] ?? _Agenda();

  /// Only the client and the prestataire who accepted can read or write.
  void _requireChatParticipant(Map<String, Object?> row, int userId) {
    final hasPrestataire = row['i_id'] != null &&
        _demandeStatus(row) != DemandeServiceStatus.enAttente;
    final allowed = hasPrestataire &&
        (row['client_id'] == userId || row['i_prestataire_id'] == userId);
    if (!allowed) throw ApiError.forbidden('Accès refusé à cette conversation');
  }

  /// Best effort: the action already succeeded, so a failed notification
  /// must never turn it into an error.
  Future<void> _notify(
    int? targetId,
    int demandeId,
    String titre,
    String message,
  ) async {
    if (targetId == null) return;
    try {
      await _repository.addNotification(
        userId: targetId,
        demandeId: demandeId,
        titre: titre,
        message: message,
        now: _clock(),
      );
    } catch (e) {
      developer.log('Notification non créée : $e', name: 'servicenow');
    }
  }

  Future<void> _notifySpecialists(
    int demandeId,
    ServiceNowType type,
    String adresse,
  ) async {
    final prestataires = await _repository.listPrestataires();
    for (final prestataire in prestataires) {
      if (_specialties(prestataire['specialites']).contains(type)) {
        await _notify(prestataire['id'] as int, demandeId,
            'Nouvelle demande : ${type.label}', adresse);
      }
    }
  }

  String _newQrCode() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => _qrAlphabet[random.nextInt(_qrAlphabet.length)],
    ).join();
  }

  String _photoColumn(InterventionPhotoKind kind) => switch (kind) {
        InterventionPhotoKind.avant => 'photo_avant',
        InterventionPhotoKind.apres => 'photo_apres',
      };

  Map<String, Object?> _positionValues(
    ({double latitude, double longitude}) position,
    DateTime now,
  ) =>
      {
        'prestataire_lat': position.latitude,
        'prestataire_lng': position.longitude,
        'position_le': now.toUtc().toIso8601String(),
      };

  bool _isTracking(Map<String, Object?> row) =>
      row['i_en_route_le'] != null &&
      _interventionStatus(row) == InterventionStatus.planifiee;

  void _requireParticipant(
    Map<String, Object?> row,
    int userId,
    UserRole role,
  ) {
    final allowed = row['client_id'] == userId ||
        row['i_prestataire_id'] == userId ||
        role == UserRole.admin;
    if (!allowed) throw ApiError.forbidden('Accès refusé à cette intervention');
  }

  Set<ServiceNowType> _specialties(Object? stored) {
    if (stored is! String || stored.isEmpty) return {};
    return {
      for (final value in stored.split(','))
        if (ServiceNowType.tryParse(value) case final type?) type,
    };
  }

  double? _double(Object? value) => (value as num?)?.toDouble();

  /// Kilometres between two stored points; null when one is unknown.
  double? _distance(Object? lat1, Object? lng1, Object? lat2, Object? lng2) {
    final a = _double(lat1);
    final b = _double(lng1);
    final c = _double(lat2);
    final d = _double(lng2);
    if (a == null || b == null || c == null || d == null) return null;
    return GeoDistance.haversineKm(a, b, c, d);
  }

  void _validateDemande(
    String description,
    String adresse,
    DateTime dateSouhaitee,
    DateTime now,
  ) {
    _throwIfError(ServiceNowRules.descriptionError(description));
    _throwIfError(ServiceNowRules.addressError(adresse));
    _throwIfError(ServiceNowRules.scheduleError(dateSouhaitee, now: now));
  }

  void _throwIfError(String? message) {
    if (message != null) throw ApiError.badRequest(message);
  }

  void _requirePrestataire(UserRole role) {
    if (role != UserRole.prestataire) {
      throw ApiError.forbidden('Réservé aux prestataires');
    }
  }

  Future<Map<String, Object?>> _requireDemande(int id) async {
    final row = await _repository.findDemande(id);
    if (row == null) throw ApiError.notFound('Demande introuvable');
    return row;
  }

  Future<Map<String, Object?>> _requireIntervention(int id) async {
    final row = await _repository.findByIntervention(id);
    if (row == null) throw ApiError.notFound('Intervention introuvable');
    return row;
  }

  Future<Map<String, Object?>> _requireOwnIntervention(
    int userId,
    UserRole role,
    int interventionId,
  ) async {
    _requirePrestataire(role);
    final row = await _requireIntervention(interventionId);
    if (row['i_prestataire_id'] != userId) {
      throw ApiError.forbidden('Cette intervention ne vous est pas attribuée');
    }
    return row;
  }

  /// Moves an intervention and its request together, or not at all.
  Future<void> _move(
    int interventionId,
    int demandeId, {
    required InterventionStatus fromIntervention,
    required InterventionStatus toIntervention,
    required DemandeServiceStatus fromDemande,
    required DemandeServiceStatus toDemande,
    required DateTime now,
    required String conflictMessage,
    Map<String, Object?> values = const {},
  }) async {
    await _db.transaction((txn) async {
      final interventionMoved = await _repository.moveIntervention(
        txn,
        interventionId,
        from: fromIntervention,
        to: toIntervention,
        now: now,
        values: values,
      );
      final demandeMoved = interventionMoved &&
          await _repository.moveDemande(
            txn,
            demandeId,
            from: fromDemande,
            to: toDemande,
            now: now,
          );
      // Throwing rolls the whole database transaction back.
      if (!demandeMoved) throw ApiError.conflict(conflictMessage);
    });
  }

  Future<DemandeServiceDto> _reload(
    int id,
    int viewerId,
    UserRole viewerRole,
  ) async =>
      _toDto(await _requireDemande(id), viewerId, viewerRole);

  DemandeServiceStatus _demandeStatus(Map<String, Object?> row) =>
      DemandeServiceStatus.parse(row['statut'] as String);

  InterventionStatus _interventionStatus(Map<String, Object?> row) =>
      InterventionStatus.parse(row['i_statut'] as String);

  /// Builds the DTO seen by this viewer: phone numbers are only shared
  /// between a client and the prestataire committed to the request.
  DemandeServiceDto _toDto(
    Map<String, Object?> row,
    int viewerId,
    UserRole viewerRole, {
    double? distanceKm,
    bool specialtyMatch = false,
    bool availableOnDate = true,
  }) {
    final status = _demandeStatus(row);
    final isAdmin = viewerRole == UserRole.admin;
    final isClient = row['client_id'] == viewerId;
    final hasIntervention =
        row['i_id'] != null && status != DemandeServiceStatus.enAttente;
    final isAssigned = hasIntervention && row['i_prestataire_id'] == viewerId;
    final isLive = hasIntervention && status != DemandeServiceStatus.annulee;
    final showClientContact = isClient || isAdmin || (isAssigned && isLive);
    final showPrestataireContact = isAssigned || isAdmin || (isClient && isLive);

    return DemandeServiceDto(
      id: row['id'] as int,
      clientId: row['client_id'] as int,
      clientNom: _displayName(
        row['client_prenom'] as String,
        row['client_nom'] as String,
        full: showClientContact,
      ),
      clientTelephone:
          showClientContact ? row['client_telephone'] as String : null,
      type: ServiceNowType.parse(row['type'] as String),
      description: row['description'] as String,
      adresse: row['adresse'] as String,
      dateSouhaitee: DateTime.parse(row['date_souhaitee'] as String),
      statut: status,
      creeLe: DateTime.parse(row['cree_le'] as String),
      modifieLe: DateTime.parse(row['modifie_le'] as String),
      intervention: hasIntervention
          ? _interventionDto(
              row,
              showContact: showPrestataireContact,
              showQrCode: isClient,
            )
          : null,
      latitude: _double(row['latitude']),
      longitude: _double(row['longitude']),
      distanceKm: distanceKm,
      specialiteCorrespond: specialtyMatch,
      disponibleALaDate: availableOnDate,
    );
  }

  InterventionDto _interventionDto(
    Map<String, Object?> row, {
    required bool showContact,
    required bool showQrCode,
  }) {
    final prenom = row['p_prenom'] as String?;
    final nom = row['p_nom'] as String?;
    return InterventionDto(
      id: row['i_id'] as int,
      demandeId: row['id'] as int,
      prestataireId: row['i_prestataire_id'] as int?,
      prestataireNom: prenom == null || nom == null
          ? null
          : _displayName(prenom, nom, full: showContact),
      prestataireTelephone: showContact ? row['p_telephone'] as String? : null,
      datePrevue: DateTime.parse(row['i_date_prevue'] as String),
      dateDebut: _date(row['i_date_debut']),
      dateFin: _date(row['i_date_fin']),
      rapport: row['i_rapport'] as String?,
      prixCentimes: row['i_prix_centimes'] as int,
      statut: _interventionStatus(row),
      transactionId: row['i_transaction_id'] as int?,
      paiementStatut: row['t_statut'] == null
          ? null
          : TransactionStatus.parse(row['t_statut'] as String),
      qrCode: showQrCode && row['i_statut'] == 'planifiee'
          ? row['i_qr_code'] as String?
          : null,
      enRouteLe: _date(row['i_en_route_le']),
      aPhotoAvant: row['i_photo_avant'] != null,
      aPhotoApres: row['i_photo_apres'] != null,
      note: row['i_note'] as int?,
      commentaire: row['i_commentaire'] as String?,
      prestataireNoteMoyenne: _double(row['p_note_moyenne']),
      prestataireNbNotes: row['p_nb_notes'] as int? ?? 0,
    );
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  /// "Prénom Nom", or "Prénom N." for people not yet working together.
  String _displayName(String prenom, String nom, {required bool full}) {
    if (full) return '$prenom $nom';
    return nom.isEmpty ? prenom : '$prenom ${nom[0]}.';
  }
}

/// What occupies a prestataire: his hours, days off and interventions.
class _Agenda {
  final List<DisponibiliteSlotDto> slots = [];
  final Set<String> joursOff = {};
  final List<DateTime> busy = [];

  bool isFreeAt(DateTime when) => ServiceNowRules.isAvailable(
        when,
        slots: slots,
        joursOff: joursOff,
        busy: busy,
      );
}
