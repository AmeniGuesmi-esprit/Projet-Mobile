import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../services/trip_service.dart';

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  return null;
}

bool _asBool(Object? v) => v is bool && v;

bool _flag(String? v) => v == '1' || v == 'true';

String _asString(Object? v) => v is String ? v : '';

/// Vehicle + trip routes (mounted behind [requireAuth]).
Router buildTripRoutes(TripService trips) {
  final router = Router();

  // ---- Véhicules ----

  router.get('/vehicles', (Request request) {
    return guard(() async {
      final list = await trips.listVehicles(request.userId);
      return jsonResponse({'items': list.map((v) => v.toJson()).toList()});
    });
  });

  router.post('/vehicles', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final nbPlaces = _asInt(body['nb_places']);
      if (nbPlaces == null) {
        throw ApiError.badRequest('nb_places (entier) requis');
      }
      final role = UserRole.parse(request.userRow['role'] as String);
      final dto = await trips.addVehicle(
        request.userId,
        role,
        marque: _asString(body['marque']),
        modele: _asString(body['modele']),
        couleur: _asString(body['couleur']),
        nbPlaces: nbPlaces,
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.delete('/vehicles/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      await trips.deleteVehicle(request.userId, int.parse(id));
      return Response(204);
    });
  });

  // ---- Trajets ----

  router.post('/trips', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final vehiculeId = _asInt(body['vehicule_id']);
      final places = _asInt(body['places']);
      final prix = _asInt(body['prix_par_place_centimes']);
      if (vehiculeId == null) {
        throw ApiError.badRequest('vehicule_id (entier) requis');
      }
      if (places == null) throw ApiError.badRequest('places (entier) requis');
      if (prix == null) {
        throw ApiError.badRequest('prix_par_place_centimes (entier) requis');
      }
      final role = UserRole.parse(request.userRow['role'] as String);
      final dto = await trips.publish(
        request.userId,
        role,
        vehiculeId: vehiculeId,
        departAdresse: _asString(body['depart_adresse']),
        departLatitude: _asDouble(body['depart_latitude']),
        departLongitude: _asDouble(body['depart_longitude']),
        arriveeAdresse: _asString(body['arrivee_adresse']),
        arriveeLatitude: _asDouble(body['arrivee_latitude']),
        arriveeLongitude: _asDouble(body['arrivee_longitude']),
        dateHeureDepart: _asString(body['date_heure_depart']),
        places: places,
        prixParPlaceCentimes: prix,
        ambiance: Ambiance.parse(
          body['ambiance'] is String
              ? body['ambiance'] as String
              : Ambiance.indifferent.apiValue,
        ),
        fumeurAccepte: _asBool(body['fumeur_accepte']),
        animauxAcceptes: _asBool(body['animaux_acceptes']),
        reserveAuxFemmes: _asBool(body['reserve_aux_femmes']),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  // Proximity search (declared before /trips/<id>).
  router.get('/trips/search', (Request request) {
    return guard(() async {
      final q = request.requestedUri.queryParameters;
      final lat = double.tryParse(q['lat'] ?? '');
      final lng = double.tryParse(q['lng'] ?? '');
      if (lat == null || lng == null) {
        throw ApiError.badRequest('lat et lng (position de départ) requis');
      }
      final ambianceParam = q['ambiance'];
      final list = await trips.search(
        request.userId,
        lat: lat,
        lng: lng,
        destLat: double.tryParse(q['dest_lat'] ?? ''),
        destLng: double.tryParse(q['dest_lng'] ?? ''),
        rayonKm: double.tryParse(q['rayon_km'] ?? '') ?? 5,
        date: q['date'],
        minSeats: int.tryParse(q['places'] ?? '') ?? 1,
        maxPriceCentimes: int.tryParse(q['prix_max_centimes'] ?? ''),
        ambiance: (ambianceParam == null || ambianceParam.isEmpty)
            ? null
            : Ambiance.parse(ambianceParam),
        nonFumeur: _flag(q['non_fumeur']),
        animaux: _flag(q['animaux']),
        femmes: _flag(q['femmes']),
        heure: q['heure'],
        fenetreMin: int.tryParse(q['fenetre_min'] ?? '') ?? 60,
        isWoman: request.userRow['sexe'] == 'femme',
      );
      return jsonResponse({'items': list.map((t) => t.toJson()).toList()});
    });
  });

  // Trips published by the connected driver (declared before /trips/<id>).
  router.get('/trips/mine', (Request request) {
    return guard(() async {
      final list = await trips.myTrips(request.userId);
      return jsonResponse({'items': list.map((t) => t.toJson()).toList()});
    });
  });

  router.get('/trips/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final dto = await trips.getTrip(int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  return router;
}
