import 'service_now_enums.dart';

/// Working hours of one day. [jour] follows `DateTime.weekday` (1 = lundi),
/// times are minutes since midnight.
class DisponibiliteSlotDto {
  const DisponibiliteSlotDto({
    required this.jour,
    required this.debutMinutes,
    required this.finMinutes,
  });

  final int jour;
  final int debutMinutes;
  final int finMinutes;

  factory DisponibiliteSlotDto.fromJson(Map<String, dynamic> json) =>
      DisponibiliteSlotDto(
        jour: json['jour'] as int,
        debutMinutes: json['debut_minutes'] as int,
        finMinutes: json['fin_minutes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'jour': jour,
        'debut_minutes': debutMinutes,
        'fin_minutes': finMinutes,
      };
}

/// A prestataire's weekly hours and days off ("2026-11-12").
class PrestataireDisponibiliteDto {
  const PrestataireDisponibiliteDto({
    required this.creneaux,
    required this.joursOff,
  });

  final List<DisponibiliteSlotDto> creneaux;
  final List<String> joursOff;

  factory PrestataireDisponibiliteDto.fromJson(Map<String, dynamic> json) =>
      PrestataireDisponibiliteDto(
        creneaux: [
          for (final slot in json['creneaux'] as List)
            DisponibiliteSlotDto.fromJson(slot as Map<String, dynamic>),
        ],
        joursOff: [
          for (final day in json['jours_off'] as List) day as String,
        ],
      );

  Map<String, dynamic> toJson() => {
        'creneaux': [for (final slot in creneaux) slot.toJson()],
        'jours_off': joursOff,
      };
}

/// One message of the conversation attached to a request.
class ServiceNowMessageDto {
  const ServiceNowMessageDto({
    required this.id,
    required this.demandeId,
    required this.auteurNom,
    required this.contenu,
    required this.creeLe,
    this.auteurId,
  });

  final int id;
  final int demandeId;

  /// Null once the author has deleted his account.
  final int? auteurId;
  final String auteurNom;
  final String contenu;
  final DateTime creeLe;

  factory ServiceNowMessageDto.fromJson(Map<String, dynamic> json) =>
      ServiceNowMessageDto(
        id: json['id'] as int,
        demandeId: json['demande_id'] as int,
        auteurId: json['auteur_id'] as int?,
        auteurNom: json['auteur_nom'] as String,
        contenu: json['contenu'] as String,
        creeLe: DateTime.parse(json['cree_le'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'demande_id': demandeId,
        'auteur_id': auteurId,
        'auteur_nom': auteurNom,
        'contenu': contenu,
        'cree_le': creeLe.toUtc().toIso8601String(),
      };
}

/// A message waiting to be shown on a user's phone.
class ServiceNowNotificationDto {
  const ServiceNowNotificationDto({
    required this.id,
    required this.demandeId,
    required this.titre,
    required this.message,
  });

  final int id;
  final int demandeId;
  final String titre;
  final String message;

  factory ServiceNowNotificationDto.fromJson(Map<String, dynamic> json) =>
      ServiceNowNotificationDto(
        id: json['id'] as int,
        demandeId: json['demande_id'] as int,
        titre: json['titre'] as String,
        message: json['message'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'demande_id': demandeId,
        'titre': titre,
        'message': message,
      };
}

/// One address found by the address search.
class GeocodeResultDto {
  const GeocodeResultDto({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  factory GeocodeResultDto.fromJson(Map<String, dynamic> json) =>
      GeocodeResultDto(
        label: json['label'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// Suggested price range for a type of service.
class PriceEstimateDto {
  const PriceEstimateDto({
    required this.minCentimes,
    required this.maxCentimes,
    required this.basedOn,
  });

  final int minCentimes;
  final int maxCentimes;

  /// Number of past interventions used; 0 for the usual market range.
  final int basedOn;

  factory PriceEstimateDto.fromJson(Map<String, dynamic> json) =>
      PriceEstimateDto(
        minCentimes: json['min_centimes'] as int,
        maxCentimes: json['max_centimes'] as int,
        basedOn: json['based_on'] as int,
      );

  Map<String, dynamic> toJson() => {
        'min_centimes': minCentimes,
        'max_centimes': maxCentimes,
        'based_on': basedOn,
      };
}

/// A prestataire recommended for a request (never his contact details).
class NearbyPrestataireDto {
  const NearbyPrestataireDto({
    required this.id,
    required this.nom,
    required this.specialiste,
    required this.nbNotes,
    this.distanceKm,
    this.noteMoyenne,
  });

  final int id;
  final String nom;
  final bool specialiste;
  final int nbNotes;
  final double? distanceKm;
  final double? noteMoyenne;

  factory NearbyPrestataireDto.fromJson(Map<String, dynamic> json) =>
      NearbyPrestataireDto(
        id: json['id'] as int,
        nom: json['nom'] as String,
        specialiste: json['specialiste'] as bool,
        nbNotes: json['nb_notes'] as int,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        noteMoyenne: (json['note_moyenne'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'specialiste': specialiste,
        'nb_notes': nbNotes,
        'distance_km': distanceKm,
        'note_moyenne': noteMoyenne,
      };
}

/// What a prestataire offers and where he works from.
class PrestataireProfilDto {
  const PrestataireProfilDto({
    required this.specialites,
    this.latitude,
    this.longitude,
  });

  final Set<ServiceNowType> specialites;
  final double? latitude;
  final double? longitude;

  factory PrestataireProfilDto.fromJson(Map<String, dynamic> json) =>
      PrestataireProfilDto(
        specialites: {
          for (final value in json['specialites'] as List)
            ServiceNowType.parse(value as String),
        },
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'specialites': [for (final type in specialites) type.apiValue],
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// Live position of a prestataire on his way, and the road to the client.
class ServiceTrackingDto {
  const ServiceTrackingDto({
    required this.enRoute,
    required this.approximatif,
    this.points = const [],
    this.latitude,
    this.longitude,
    this.positionLe,
    this.destinationLatitude,
    this.destinationLongitude,
    this.distanceMetres,
    this.dureeSecondes,
  });

  final bool enRoute;

  /// True when the routing service failed: straight-line estimate.
  final bool approximatif;

  /// Road to follow, `(latitude, longitude)` pairs.
  final List<(double, double)> points;
  final double? latitude;
  final double? longitude;
  final DateTime? positionLe;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final int? distanceMetres;
  final int? dureeSecondes;

  factory ServiceTrackingDto.fromJson(Map<String, dynamic> json) =>
      ServiceTrackingDto(
        enRoute: json['en_route'] as bool,
        approximatif: json['approximatif'] as bool,
        points: [
          for (final point in json['points'] as List)
            (
              ((point as List)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ),
        ],
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        positionLe: json['position_le'] == null
            ? null
            : DateTime.parse(json['position_le'] as String),
        destinationLatitude: (json['destination_latitude'] as num?)?.toDouble(),
        destinationLongitude:
            (json['destination_longitude'] as num?)?.toDouble(),
        distanceMetres: json['distance_metres'] as int?,
        dureeSecondes: json['duree_secondes'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'en_route': enRoute,
        'approximatif': approximatif,
        'points': [
          for (final (lat, lng) in points) [lat, lng],
        ],
        'latitude': latitude,
        'longitude': longitude,
        'position_le': positionLe?.toUtc().toIso8601String(),
        'destination_latitude': destinationLatitude,
        'destination_longitude': destinationLongitude,
        'distance_metres': distanceMetres,
        'duree_secondes': dureeSecondes,
      };
}
