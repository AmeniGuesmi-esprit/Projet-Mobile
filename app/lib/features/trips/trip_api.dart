import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../search/trip_search_query.dart';

/// Typed vehicle + trip endpoints over [ApiClient].
class TripApi {
  TripApi(this._client);

  final ApiClient _client;

  Future<List<VehicleDto>> listVehicles() async {
    final data = await _client.getJson('/vehicles');
    return (data['items'] as List)
        .map((e) => VehicleDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VehicleDto> addVehicle({
    required String marque,
    required String modele,
    required String couleur,
    required int nbPlaces,
  }) async {
    final data = await _client.postJson('/vehicles', {
      'marque': marque,
      'modele': modele,
      'couleur': couleur,
      'nb_places': nbPlaces,
    });
    return VehicleDto.fromJson(data);
  }

  Future<TripDto> publish({
    required int vehiculeId,
    required String departAdresse,
    required double departLatitude,
    required double departLongitude,
    required String arriveeAdresse,
    required double arriveeLatitude,
    required double arriveeLongitude,
    required DateTime dateHeureDepart,
    required int places,
    required int prixParPlaceCentimes,
    required Ambiance ambiance,
    required bool fumeurAccepte,
    required bool animauxAcceptes,
    required bool reserveAuxFemmes,
  }) async {
    final data = await _client.postJson('/trips', {
      'vehicule_id': vehiculeId,
      'depart_adresse': departAdresse,
      'depart_latitude': departLatitude,
      'depart_longitude': departLongitude,
      'arrivee_adresse': arriveeAdresse,
      'arrivee_latitude': arriveeLatitude,
      'arrivee_longitude': arriveeLongitude,
      // Local time without zone, e.g. 2026-10-30T08:10:00.000
      'date_heure_depart': dateHeureDepart.toIso8601String(),
      'places': places,
      'prix_par_place_centimes': prixParPlaceCentimes,
      'ambiance': ambiance.apiValue,
      'fumeur_accepte': fumeurAccepte,
      'animaux_acceptes': animauxAcceptes,
      'reserve_aux_femmes': reserveAuxFemmes,
    });
    return TripDto.fromJson(data);
  }

  /// Proximity search for passengers (open trips around the departure).
  Future<List<TripDto>> search(TripSearchQuery query) async {
    final data = await _client.getJson('/trips/search?${query.queryString}');
    return (data['items'] as List)
        .map((e) => TripDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TripDto>> myTrips() async {
    final data = await _client.getJson('/trips/mine');
    return (data['items'] as List)
        .map((e) => TripDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
