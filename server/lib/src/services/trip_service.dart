import 'dart:math' as math;

import 'package:proxilife_shared/proxilife_shared.dart';

import '../api_error.dart';
import '../repositories/trip_repository.dart';
import '../repositories/vehicle_repository.dart';

/// Business rules for vehicles and trip publication.
class TripService {
  TripService({required this.vehicles, required this.trips});

  final VehicleRepository vehicles;
  final TripRepository trips;

  static const int maxVehiclesPerUser = 5;

  void _requireDriver(UserRole role, String action) {
    if (role != UserRole.conducteur) {
      throw ApiError.forbidden('Seuls les conducteurs peuvent $action');
    }
  }

  // ------------------------------------------------------------ vehicles --

  Future<List<VehicleDto>> listVehicles(int userId) async {
    final rows = await vehicles.listForUser(userId);
    return rows.map(vehicles.toDto).toList();
  }

  Future<VehicleDto> addVehicle(
    int userId,
    UserRole role, {
    required String marque,
    required String modele,
    required String couleur,
    required int nbPlaces,
  }) async {
    _requireDriver(role, 'ajouter un véhicule');
    marque = marque.trim();
    modele = modele.trim();
    couleur = couleur.trim();

    if (marque.isEmpty || marque.length > 40) {
      throw ApiError.badRequest('Marque invalide (1 à 40 caractères)');
    }
    if (modele.isEmpty || modele.length > 40) {
      throw ApiError.badRequest('Modèle invalide (1 à 40 caractères)');
    }
    if (couleur.isEmpty || couleur.length > 30) {
      throw ApiError.badRequest('Couleur invalide (1 à 30 caractères)');
    }
    final seatsError = TripRules.seatsError(nbPlaces);
    if (seatsError != null) throw ApiError.badRequest(seatsError);

    if (await vehicles.countForUser(userId) >= maxVehiclesPerUser) {
      throw ApiError.conflict(
          'Vous ne pouvez pas enregistrer plus de $maxVehiclesPerUser véhicules');
    }

    final id = await vehicles.insert(
      utilisateurId: userId,
      marque: marque,
      modele: modele,
      couleur: couleur,
      nbPlaces: nbPlaces,
    );
    return vehicles.toDto((await vehicles.findById(id))!);
  }

  Future<void> deleteVehicle(int userId, int vehicleId) async {
    final row = await vehicles.findById(vehicleId);
    if (row == null || row['utilisateur_id'] != userId) {
      throw ApiError.notFound('Véhicule introuvable');
    }
    if (await vehicles.hasTrips(vehicleId)) {
      throw ApiError.conflict(
          'Ce véhicule est utilisé par un ou plusieurs trajets');
    }
    await vehicles.delete(vehicleId);
  }

  // --------------------------------------------------------------- trips --

  /// Publishes a trip. All numbers are validated here (authoritative); the
  /// departure time may be given with or without a time zone and is stored as
  /// local ISO-8601 so that string comparison matches chronological order.
  Future<TripDto> publish(
    int userId,
    UserRole role, {
    required int vehiculeId,
    required String departAdresse,
    required double? departLatitude,
    required double? departLongitude,
    required String arriveeAdresse,
    required double? arriveeLatitude,
    required double? arriveeLongitude,
    required String dateHeureDepart,
    required int places,
    required int prixParPlaceCentimes,
    required Ambiance ambiance,
    required bool fumeurAccepte,
    required bool animauxAcceptes,
    required bool reserveAuxFemmes,
  }) async {
    _requireDriver(role, 'publier un trajet');

    final departError = TripRules.placeError(
        'Départ', departAdresse, departLatitude, departLongitude);
    if (departError != null) throw ApiError.badRequest(departError);
    final arriveeError = TripRules.placeError(
        'Arrivée', arriveeAdresse, arriveeLatitude, arriveeLongitude);
    if (arriveeError != null) throw ApiError.badRequest(arriveeError);

    final distance = TripRules.distanceKm(
        departLatitude!, departLongitude!, arriveeLatitude!, arriveeLongitude!);
    if (distance < TripRules.minTripDistanceKm) {
      throw ApiError.badRequest('Le départ et l\'arrivée sont identiques');
    }

    final parsed = DateTime.tryParse(dateHeureDepart.trim());
    if (parsed == null) {
      throw ApiError.badRequest('Date et heure de départ invalides');
    }
    final departure = parsed.toLocal();
    final now = DateTime.now();
    if (!departure.isAfter(now)) {
      throw ApiError.badRequest('Le départ doit être dans le futur');
    }
    if (departure.isAfter(now.add(const Duration(days: 365)))) {
      throw ApiError.badRequest(
          'Le départ ne peut pas dépasser un an à l\'avance');
    }

    final vehicle = await vehicles.findById(vehiculeId);
    if (vehicle == null || vehicle['utilisateur_id'] != userId) {
      throw ApiError.notFound('Véhicule introuvable');
    }

    final seatsError = TripRules.seatsError(places);
    if (seatsError != null) throw ApiError.badRequest(seatsError);
    if (places > (vehicle['nb_places'] as int)) {
      throw ApiError.badRequest(
          'Ce véhicule n\'a que ${vehicle['nb_places']} place(s) passager');
    }

    final priceError = TripRules.priceError(prixParPlaceCentimes);
    if (priceError != null) throw ApiError.badRequest(priceError);

    final dateIso = departure.toIso8601String();
    if (await trips.driverHasActiveTripAt(userId, dateIso)) {
      throw ApiError.conflict('Vous avez déjà un trajet prévu à cette heure');
    }

    final id = await trips.insert(
      conducteurId: userId,
      vehiculeId: vehiculeId,
      departAdresse: departAdresse.trim(),
      departLatitude: departLatitude,
      departLongitude: departLongitude,
      arriveeAdresse: arriveeAdresse.trim(),
      arriveeLatitude: arriveeLatitude,
      arriveeLongitude: arriveeLongitude,
      dateHeureDepartIso: dateIso,
      places: places,
      prixParPlaceCentimes: prixParPlaceCentimes,
      ambiance: ambiance,
      fumeurAccepte: fumeurAccepte,
      animauxAcceptes: animauxAcceptes,
      reserveAuxFemmes: reserveAuxFemmes,
    );
    return trips.toDto((await trips.findById(id))!);
  }

  Future<List<TripDto>> myTrips(int userId) async {
    final rows = await trips.listForDriver(userId);
    return rows.map((r) => trips.toDto(r)).toList();
  }

  /// Proximity search: open, future trips whose departure is within
  /// [rayonKm] of the passenger's position (and, when a destination is given,
  /// whose arrival is within [rayonKm] of it). Women-only trips are only shown
  /// to users who declared being a woman. Own trips are never listed.
  Future<List<TripDto>> search(
    int userId, {
    required double lat,
    required double lng,
    double? destLat,
    double? destLng,
    required double rayonKm,
    String? date,
    int minSeats = 1,
    int? maxPriceCentimes,
    Ambiance? ambiance,
    bool nonFumeur = false,
    bool animaux = false,
    bool femmes = false,
    String? heure,
    int fenetreMin = 60,
    required bool isWoman,
  }) async {
    if (!TripRules.isValidLatitude(lat) || !TripRules.isValidLongitude(lng)) {
      throw ApiError.badRequest('Position invalide');
    }
    if (rayonKm < 1 || rayonKm > 50) {
      throw ApiError.badRequest('Le rayon doit être entre 1 et 50 km');
    }
    final seatsError = TripRules.seatsError(minSeats);
    if (seatsError != null) throw ApiError.badRequest(seatsError);
    final dest = (destLat != null &&
            destLng != null &&
            TripRules.isValidLatitude(destLat) &&
            TripRules.isValidLongitude(destLng))
        ? (lat: destLat, lng: destLng)
        : null;

    // Time window: from now (or the start of the chosen day) to the end of day.
    final now = DateTime.now();
    var from = now;
    String? toIso;
    DateTime? target; // heure de départ souhaitée (matching horaire)
    if (heure != null && heure.isNotEmpty) {
      final parsed = DateTime.tryParse(heure);
      if (parsed == null) {
        throw ApiError.badRequest('Heure souhaitée invalide (ISO 8601)');
      }
      if (fenetreMin < 10 || fenetreMin > 240) {
        throw ApiError.badRequest(
            'La fenêtre horaire doit être entre 10 et 240 minutes');
      }
      target = parsed.toLocal();
      final start = target.subtract(Duration(minutes: fenetreMin));
      if (start.isAfter(now)) from = start;
      toIso = target.add(Duration(minutes: fenetreMin)).toIso8601String();
    } else if (date != null && date.isNotEmpty) {
      final day = DateTime.tryParse(date);
      if (day == null) throw ApiError.badRequest('Date invalide (AAAA-MM-JJ)');
      final start = DateTime(day.year, day.month, day.day);
      if (start.isAfter(now)) from = start;
      toIso = DateTime(day.year, day.month, day.day + 1).toIso8601String();
    }

    // Bounding box (1 degree of latitude ~ 111 km).
    final dLat = rayonKm / 111.0;
    final dLng = rayonKm / (111.0 * math.max(0.01, math.cos(lat * math.pi / 180)));

    final rows = await trips.searchCandidates(
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLng: lng - dLng,
      maxLng: lng + dLng,
      fromIso: from.toIso8601String(),
      toIso: toIso,
      minSeats: minSeats,
      excludeDriverId: userId,
      maxPriceCentimes: maxPriceCentimes,
      ambiance: ambiance?.apiValue,
      nonFumeur: nonFumeur,
      animaux: animaux,
      femmes: femmes,
      includeWomenOnly: isWoman,
    );

    double round1(double km) => (km * 10).round() / 10;
    final results = <TripDto>[];
    for (final row in rows) {
      final dDepart = TripRules.distanceKm(
        lat,
        lng,
        (row['depart_latitude'] as num).toDouble(),
        (row['depart_longitude'] as num).toDouble(),
      );
      if (dDepart > rayonKm) continue;
      double? dArrivee;
      if (dest != null) {
        dArrivee = TripRules.distanceKm(
          dest.lat,
          dest.lng,
          (row['arrivee_latitude'] as num).toDouble(),
          (row['arrivee_longitude'] as num).toDouble(),
        );
        if (dArrivee > rayonKm) continue;
      }
      int? ecart;
      if (target != null) {
        final dep = DateTime.parse(row['date_heure_depart'] as String);
        ecart = dep.difference(target).inMinutes.abs();
      }
      final ranked = dest != null || target != null;
      results.add(trips.toDto(
        row,
        distanceDepartKm: round1(dDepart),
        distanceArriveeKm: dArrivee == null ? null : round1(dArrivee),
        scoreMatching: ranked
            ? _matchScore(
                dDepart: dDepart,
                dArrivee: dArrivee,
                rayonKm: rayonKm,
                ecartMin: ecart,
                fenetreMin: fenetreMin,
              )
            : null,
        ecartHeureMin: ecart,
      ));
    }
    // Best matches first when the passenger gave a destination and/or a time;
    // otherwise keep the chronological order coming from SQL.
    if (dest != null || target != null) {
      results.sort((a, b) {
        final byScore = (b.scoreMatching ?? 0).compareTo(a.scoreMatching ?? 0);
        return byScore != 0
            ? byScore
            : a.dateHeureDepartIso.compareTo(b.dateHeureDepartIso);
      });
    }
    return results.length > 50 ? results.sublist(0, 50) : results;
  }

  /// Matching score 0-100. Each criterion gives 1.0 (perfect) to 0.0 (at the
  /// limit of the radius / time window). Weights: departure 40 %, arrival 30 %,
  /// time 30 %; criteria the passenger did not give are left out and the
  /// remaining weights are re-normalised.
  int _matchScore({
    required double dDepart,
    required double? dArrivee,
    required double rayonKm,
    required int? ecartMin,
    required int fenetreMin,
  }) {
    double part(double value, double max) =>
        (1 - value / max).clamp(0.0, 1.0).toDouble();
    var sum = 0.4 * part(dDepart, rayonKm);
    var weights = 0.4;
    if (dArrivee != null) {
      sum += 0.3 * part(dArrivee, rayonKm);
      weights += 0.3;
    }
    if (ecartMin != null) {
      sum += 0.3 * part(ecartMin.toDouble(), fenetreMin.toDouble());
      weights += 0.3;
    }
    return (100 * sum / weights).round();
  }

  Future<TripDto> getTrip(int tripId) async {
    final row = await trips.findById(tripId);
    if (row == null) throw ApiError.notFound('Trajet introuvable');
    return trips.toDto(row);
  }
}
