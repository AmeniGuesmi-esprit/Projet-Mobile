import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../repositories/reservation_repository.dart';
import '../repositories/trip_repository.dart';
import '../repositories/user_repository.dart';

/// Business rules of the reservations: request, accept / refuse (driver),
/// cancel (passenger). Seats leave `trajet.places_disponibles` only when the
/// driver accepts, and come back when an accepted reservation is cancelled.
///
/// Every state change runs in ONE transaction. DTOs are built after the
/// transaction ends (never use the plain database while a transaction is open:
/// it would wait for it forever).
class ReservationService {
  ReservationService({
    required this.db,
    required this.reservations,
    required this.trips,
    required this.users,
  });

  final Database db;
  final ReservationRepository reservations;
  final TripRepository trips;
  final UserRepository users;

  Future<Map<String, Object?>?> _tripRow(DatabaseExecutor e, int tripId) async {
    final rows =
        await e.rawQuery('${TripRepository.selectSql} WHERE t.id = ?', [tripId]);
    return rows.isEmpty ? null : rows.first;
  }

  bool _isFuture(Map<String, Object?> trip) =>
      DateTime.parse(trip['date_heure_depart'] as String)
          .isAfter(DateTime.now());

  // ------------------------------------------------------------- request --

  Future<TripReservationDto> request(int userId, int tripId, int nbPlaces) async {
    final seatsError = TripRules.seatsError(nbPlaces);
    if (seatsError != null) throw ApiError.badRequest(seatsError);

    final user = await users.findById(userId);
    if (user == null) throw ApiError.notFound('Compte introuvable');
    final isWoman = user['sexe'] == 'femme';

    final id = await db.transaction<int>((txn) async {
      final trip = await _tripRow(txn, tripId);
      if (trip == null) throw ApiError.notFound('Trajet introuvable');
      if (trip['conducteur_id'] == userId) {
        throw ApiError.badRequest(
            'Vous ne pouvez pas réserver votre propre trajet');
      }
      if (!TripStatus.parse(trip['statut'] as String).isBookable) {
        throw ApiError.conflict('Ce trajet n\'accepte plus de réservations');
      }
      if (!_isFuture(trip)) {
        throw ApiError.conflict('Ce trajet est déjà parti');
      }
      if ((trip['reserve_aux_femmes'] as int) == 1 && !isWoman) {
        throw ApiError.forbidden(
            'Ce trajet est réservé aux femmes (selon le sexe déclaré dans le profil)');
      }
      if (nbPlaces > (trip['places_disponibles'] as int)) {
        throw ApiError.conflict(
            'Il ne reste que ${trip['places_disponibles']} place(s) sur ce trajet');
      }
      if (await reservations.hasActive(txn, tripId, userId)) {
        throw ApiError.conflict('Vous avez déjà une réservation sur ce trajet');
      }
      return reservations.insert(
        txn,
        tripId: tripId,
        passagerId: userId,
        nbPlaces: nbPlaces,
      );
    });
    return _dto(id);
  }

  // ------------------------------------------------------ driver decision --

  /// Loads a PENDING reservation of one of the driver's trips, or throws.
  Future<(Map<String, Object?>, Map<String, Object?>)> _pendingOfDriver(
    DatabaseExecutor txn,
    int driverId,
    int reservationId,
  ) async {
    final res = await reservations.findById(reservationId, executor: txn);
    if (res == null) throw ApiError.notFound('Demande introuvable');
    final trip = await _tripRow(txn, res['trajet_id'] as int);
    if (trip == null || trip['conducteur_id'] != driverId) {
      throw ApiError.notFound('Demande introuvable');
    }
    if (res['statut'] != TripReservationStatus.enAttente.apiValue) {
      throw ApiError.conflict('Cette demande a déjà été traitée');
    }
    return (res, trip);
  }

  Future<TripReservationDto> accept(int driverId, int reservationId) async {
    await db.transaction<void>((txn) async {
      final (res, trip) = await _pendingOfDriver(txn, driverId, reservationId);
      if (!TripStatus.parse(trip['statut'] as String).isBookable) {
        throw ApiError.conflict('Ce trajet n\'accepte plus de réservations');
      }
      if (!_isFuture(trip)) throw ApiError.conflict('Ce trajet est déjà parti');

      final seats = res['nb_places'] as int;
      final available = trip['places_disponibles'] as int;
      if (seats > available) {
        throw ApiError.conflict(
            'Il ne reste pas assez de places pour accepter cette demande');
      }
      await reservations.setStatus(
          txn, reservationId, TripReservationStatus.acceptee);
      final left = available - seats;
      await txn.update(
        'trajet',
        {
          'places_disponibles': left,
          'statut': (left == 0 ? TripStatus.complet : TripStatus.ouvert).apiValue,
        },
        where: 'id = ?',
        whereArgs: [trip['id']],
      );
    });
    return _dto(reservationId);
  }

  Future<TripReservationDto> refuse(int driverId, int reservationId) async {
    await db.transaction<void>((txn) async {
      await _pendingOfDriver(txn, driverId, reservationId);
      await reservations.setStatus(
          txn, reservationId, TripReservationStatus.refusee);
    });
    return _dto(reservationId);
  }

  // -------------------------------------------------------------- cancel --

  Future<TripReservationDto> cancel(int userId, int reservationId) async {
    await db.transaction<void>((txn) async {
      final res = await reservations.findById(reservationId, executor: txn);
      if (res == null || res['passager_id'] != userId) {
        throw ApiError.notFound('Réservation introuvable');
      }
      final status = TripReservationStatus.parse(res['statut'] as String);
      if (!status.isActive) {
        throw ApiError.conflict('Cette réservation ne peut plus être annulée');
      }
      final trip = await _tripRow(txn, res['trajet_id'] as int);
      if (trip == null) throw ApiError.notFound('Trajet introuvable');
      if (!_isFuture(trip)) {
        throw ApiError.conflict('Le trajet est déjà parti, annulation impossible');
      }

      await reservations.setStatus(
          txn, reservationId, TripReservationStatus.annulee);

      // An accepted reservation had taken seats: give them back.
      if (status == TripReservationStatus.acceptee) {
        final total = trip['places_totales'] as int;
        var restored =
            (trip['places_disponibles'] as int) + (res['nb_places'] as int);
        if (restored > total) restored = total;
        final tripStatus = TripStatus.parse(trip['statut'] as String);
        await txn.update(
          'trajet',
          {
            'places_disponibles': restored,
            if (tripStatus == TripStatus.complet)
              'statut': TripStatus.ouvert.apiValue,
          },
          where: 'id = ?',
          whereArgs: [trip['id']],
        );
      }
    });
    return _dto(reservationId);
  }

  // ------------------------------------------------------------ boarding --
  //
  // The driver's app displays a code that changes every [codeStep] (QR code, or
  // broadcast over Bluetooth). It is HMAC-SHA256(trip secret, tripId:window),
  // so it cannot be guessed nor reused later. The passenger sends it with
  // his GPS position; the server checks that he is at the departure point,
  // inside the boarding window, and that the reservation is accepted.

  static const Duration codeStep = Duration(seconds: 30);
  static const Duration boardingOpensBefore = Duration(minutes: 30);
  static const Duration boardingClosesAfter = Duration(minutes: 60);
  static const double maxBoardingDistanceKm = 0.5;
  static const int maxBoardingAttempts = 5;

  int _windowOf(DateTime t) =>
      t.millisecondsSinceEpoch ~/ codeStep.inMilliseconds;

  String _codeFor(String secret, int tripId, int window) {
    final mac = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$tripId:$window'));
    return mac.toString().substring(0, 8).toUpperCase();
  }

  String _newSecret() {
    final rnd = math.Random.secure();
    return List.generate(
      32,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _requireBoardingWindow(Map<String, Object?> trip) {
    final status = TripStatus.parse(trip['statut'] as String);
    if (status != TripStatus.ouvert && status != TripStatus.complet) {
      throw ApiError.conflict('Ce trajet n\'est plus actif');
    }
    final departure = DateTime.parse(trip['date_heure_depart'] as String);
    final now = DateTime.now();
    if (now.isBefore(departure.subtract(boardingOpensBefore))) {
      throw ApiError.conflict(
          'L\'embarquement ouvre ${boardingOpensBefore.inMinutes} minutes avant le départ');
    }
    if (now.isAfter(departure.add(boardingClosesAfter))) {
      throw ApiError.conflict('L\'embarquement est terminé pour ce trajet');
    }
  }

  /// Driver: current boarding code of one of his trips.
  Future<BoardingCodeDto> boardingCode(int driverId, int tripId) async {
    final trip = await trips.findById(tripId);
    if (trip == null || trip['conducteur_id'] != driverId) {
      throw ApiError.notFound('Trajet introuvable');
    }
    _requireBoardingWindow(trip);

    var secret = trip['code_embarquement_secret'] as String?;
    if (secret == null || secret.isEmpty) {
      // Only set when still empty, so two simultaneous calls agree.
      await db.rawUpdate(
        'UPDATE trajet SET code_embarquement_secret = ? '
        'WHERE id = ? AND code_embarquement_secret IS NULL',
        [_newSecret(), tripId],
      );
      final fresh = await trips.findById(tripId);
      secret = fresh!['code_embarquement_secret'] as String;
    }

    final now = DateTime.now();
    final window = _windowOf(now);
    final nextStartMs = (window + 1) * codeStep.inMilliseconds;
    final expiresIn =
        ((nextStartMs - now.millisecondsSinceEpoch) / 1000).ceil();
    final code = _codeFor(secret, tripId, window);
    return BoardingCodeDto(
      tripId: tripId,
      code: code,
      payload: 'proxilife:board:$tripId:$code',
      expiresInSeconds: expiresIn,
      stepSeconds: codeStep.inSeconds,
    );
  }

  /// Passenger: confirms he got into the right vehicle.
  Future<TripReservationDto> confirmBoarding(
    int userId,
    int reservationId, {
    required String code,
    required BoardingMethod method,
    required double? lat,
    required double? lng,
  }) async {
    if (lat == null ||
        lng == null ||
        !TripRules.isValidLatitude(lat) ||
        !TripRules.isValidLongitude(lng)) {
      throw ApiError.badRequest('Position GPS requise pour confirmer l\'embarquement');
    }
    final submitted = code.trim().toUpperCase();

    // A wrong code must be counted even though the request fails, so the
    // transaction RETURNS false (and commits the counter) instead of throwing.
    final ok = await db.transaction<bool>((txn) async {
      final res = await reservations.findById(reservationId, executor: txn);
      if (res == null || res['passager_id'] != userId) {
        throw ApiError.notFound('Réservation introuvable');
      }
      if (res['statut'] != TripReservationStatus.acceptee.apiValue) {
        throw ApiError.conflict(
            'Seule une réservation acceptée peut être embarquée');
      }
      if (res['embarque_le'] != null) {
        throw ApiError.conflict('Embarquement déjà confirmé');
      }
      if ((res['embarque_tentatives'] as int) >= maxBoardingAttempts) {
        throw ApiError.forbidden(
            'Trop de tentatives. Demandez au conducteur de vérifier votre réservation.');
      }
      final trip = await _tripRow(txn, res['trajet_id'] as int);
      if (trip == null) throw ApiError.notFound('Trajet introuvable');
      _requireBoardingWindow(trip);

      final distance = TripRules.distanceKm(
        lat,
        lng,
        (trip['depart_latitude'] as num).toDouble(),
        (trip['depart_longitude'] as num).toDouble(),
      );
      if (distance > maxBoardingDistanceKm) {
        throw ApiError.badRequest(
            'Vous êtes trop loin du point de départ (${(distance * 1000).round()} m)');
      }

      final secret = trip['code_embarquement_secret'] as String?;
      if (secret == null || secret.isEmpty) {
        throw ApiError.conflict(
            'Le conducteur n\'a pas encore ouvert l\'embarquement');
      }
      final tripId = trip['id'] as int;
      final window = _windowOf(DateTime.now());
      // Current and previous step: tolerates a scan right at a renewal.
      final valid = submitted == _codeFor(secret, tripId, window) ||
          submitted == _codeFor(secret, tripId, window - 1);
      if (!valid) {
        await txn.rawUpdate(
          'UPDATE reservation_trajet SET embarque_tentatives = embarque_tentatives + 1 '
          'WHERE id = ?',
          [reservationId],
        );
        return false;
      }
      await txn.update(
        'reservation_trajet',
        {
          'embarque_le': DateTime.now().toIso8601String(),
          'embarque_methode': method.apiValue,
          'embarque_latitude': lat,
          'embarque_longitude': lng,
        },
        where: 'id = ?',
        whereArgs: [reservationId],
      );
      return true;
    });
    if (!ok) throw ApiError.forbidden('Code invalide ou expiré');
    return _dto(reservationId);
  }

  // --------------------------------------------------------------- lists --

  Future<List<TripReservationDto>> listMine(int userId) async {
    final rows = await reservations.listForPassenger(userId);
    return [for (final r in rows) await _dtoFromRow(r)];
  }

  Future<List<TripReservationDto>> listReceived(int driverId) async {
    final rows = await reservations.listForDriver(driverId);
    return [for (final r in rows) await _dtoFromRow(r)];
  }

  // ----------------------------------------------------------------- dto --

  Future<TripReservationDto> _dto(int id) async {
    final row = await reservations.findById(id);
    if (row == null) throw ApiError.notFound('Réservation introuvable');
    return _dtoFromRow(row);
  }

  Future<TripReservationDto> _dtoFromRow(Map<String, Object?> row) async {
    final tripRow = await _tripRow(db, row['trajet_id'] as int);
    final passager = await users.findById(row['passager_id'] as int);
    if (tripRow == null || passager == null) {
      throw ApiError.notFound('Réservation introuvable');
    }
    final nom = passager['nom'] as String;
    final initiale = nom.isEmpty ? '' : ' ${nom.substring(0, 1).toUpperCase()}.';
    final nbPlaces = row['nb_places'] as int;
    return TripReservationDto(
      id: row['id'] as int,
      trajet: trips.toDto(tripRow),
      passagerId: row['passager_id'] as int,
      passagerNom: '${passager['prenom']}$initiale',
      passagerPhoto: passager['photo'] as String?,
      nbPlaces: nbPlaces,
      statut: TripReservationStatus.parse(row['statut'] as String),
      dateReservationIso: row['date_reservation'] as String,
      dateDecisionIso: row['date_decision'] as String?,
      montantCentimes: nbPlaces * (tripRow['prix_par_place_centimes'] as int),
      embarqueLeIso: row['embarque_le'] as String?,
      embarqueMethode: row['embarque_methode'] == null
          ? null
          : BoardingMethod.parse(row['embarque_methode'] as String),
    );
  }
}
