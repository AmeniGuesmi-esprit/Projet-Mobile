import '../trip_enums.dart';
import 'vehicle_dto.dart';

/// A published trip as seen by the client. Prices are whole centimes.
/// The driver is exposed as "Prénom N." only (no phone, no e-mail).
class TripDto {
  const TripDto({
    required this.id,
    required this.conducteurId,
    required this.conducteurNom,
    required this.vehicule,
    required this.departAdresse,
    required this.departLatitude,
    required this.departLongitude,
    required this.arriveeAdresse,
    required this.arriveeLatitude,
    required this.arriveeLongitude,
    required this.dateHeureDepartIso,
    required this.placesDisponibles,
    required this.placesTotales,
    required this.prixParPlaceCentimes,
    required this.devise,
    required this.statut,
    required this.ambiance,
    required this.fumeurAccepte,
    required this.animauxAcceptes,
    required this.reserveAuxFemmes,
    this.conducteurPhoto,
    this.noteMoyenne,
    this.nbAvis = 0,
    this.motifAnnulation,
    this.distanceDepartKm,
    this.distanceArriveeKm,
    this.scoreMatching,
    this.ecartHeureMin,
  });

  final int id;
  final int conducteurId;
  final String conducteurNom;
  final String? conducteurPhoto;
  final double? noteMoyenne;
  final int nbAvis;
  final VehicleDto vehicule;

  final String departAdresse;
  final double departLatitude;
  final double departLongitude;
  final String arriveeAdresse;
  final double arriveeLatitude;
  final double arriveeLongitude;

  final String dateHeureDepartIso;
  final int placesDisponibles;
  final int placesTotales;
  final int prixParPlaceCentimes;
  final String devise;
  final TripStatus statut;
  final String? motifAnnulation;

  final Ambiance ambiance;
  final bool fumeurAccepte;
  final bool animauxAcceptes;
  final bool reserveAuxFemmes;

  /// Only filled by the proximity search.
  final double? distanceDepartKm;
  final double? distanceArriveeKm;

  /// Matching 0-100 (départ, arrivée, horaire) ; only filled by the search
  /// when a destination and/or a desired time was given.
  final int? scoreMatching;

  /// Gap in minutes with the desired departure time (search only).
  final int? ecartHeureMin;

  DateTime get dateHeureDepart => DateTime.parse(dateHeureDepartIso);

  factory TripDto.fromJson(Map<String, dynamic> json) => TripDto(
        id: json['id'] as int,
        conducteurId: json['conducteur_id'] as int,
        conducteurNom: json['conducteur_nom'] as String,
        conducteurPhoto: json['conducteur_photo'] as String?,
        noteMoyenne: (json['note_moyenne'] as num?)?.toDouble(),
        nbAvis: json['nb_avis'] as int? ?? 0,
        vehicule: VehicleDto.fromJson(json['vehicule'] as Map<String, dynamic>),
        departAdresse: json['depart_adresse'] as String,
        departLatitude: (json['depart_latitude'] as num).toDouble(),
        departLongitude: (json['depart_longitude'] as num).toDouble(),
        arriveeAdresse: json['arrivee_adresse'] as String,
        arriveeLatitude: (json['arrivee_latitude'] as num).toDouble(),
        arriveeLongitude: (json['arrivee_longitude'] as num).toDouble(),
        dateHeureDepartIso: json['date_heure_depart'] as String,
        placesDisponibles: json['places_disponibles'] as int,
        placesTotales: json['places_totales'] as int,
        prixParPlaceCentimes: json['prix_par_place_centimes'] as int,
        devise: json['devise'] as String,
        statut: TripStatus.parse(json['statut'] as String),
        motifAnnulation: json['motif_annulation'] as String?,
        ambiance: Ambiance.parse(json['ambiance'] as String),
        fumeurAccepte: json['fumeur_accepte'] as bool,
        animauxAcceptes: json['animaux_acceptes'] as bool,
        reserveAuxFemmes: json['reserve_aux_femmes'] as bool,
        distanceDepartKm: (json['distance_depart_km'] as num?)?.toDouble(),
        distanceArriveeKm: (json['distance_arrivee_km'] as num?)?.toDouble(),
        scoreMatching: json['score_matching'] as int?,
        ecartHeureMin: json['ecart_heure_min'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conducteur_id': conducteurId,
        'conducteur_nom': conducteurNom,
        'conducteur_photo': conducteurPhoto,
        'note_moyenne': noteMoyenne,
        'nb_avis': nbAvis,
        'vehicule': vehicule.toJson(),
        'depart_adresse': departAdresse,
        'depart_latitude': departLatitude,
        'depart_longitude': departLongitude,
        'arrivee_adresse': arriveeAdresse,
        'arrivee_latitude': arriveeLatitude,
        'arrivee_longitude': arriveeLongitude,
        'date_heure_depart': dateHeureDepartIso,
        'places_disponibles': placesDisponibles,
        'places_totales': placesTotales,
        'prix_par_place_centimes': prixParPlaceCentimes,
        'devise': devise,
        'statut': statut.apiValue,
        'motif_annulation': motifAnnulation,
        'ambiance': ambiance.apiValue,
        'fumeur_accepte': fumeurAccepte,
        'animaux_acceptes': animauxAcceptes,
        'reserve_aux_femmes': reserveAuxFemmes,
        'distance_depart_km': distanceDepartKm,
        'distance_arrivee_km': distanceArriveeKm,
        'score_matching': scoreMatching,
        'ecart_heure_min': ecartHeureMin,
      };
}
