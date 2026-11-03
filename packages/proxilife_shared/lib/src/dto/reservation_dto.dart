import '../trip_enums.dart';
import 'trip_dto.dart';

/// A seat request on a trip. The passenger is exposed as "Prénom N." only
/// (no phone, no e-mail): contact details stay private.
class TripReservationDto {
  const TripReservationDto({
    required this.id,
    required this.trajet,
    required this.passagerId,
    required this.passagerNom,
    required this.nbPlaces,
    required this.statut,
    required this.dateReservationIso,
    required this.montantCentimes,
    this.passagerPhoto,
    this.dateDecisionIso,
    this.embarqueLeIso,
    this.embarqueMethode,
  });

  final int id;
  final TripDto trajet;
  final int passagerId;
  final String passagerNom;
  final String? passagerPhoto;
  final int nbPlaces;
  final TripReservationStatus statut;
  final String dateReservationIso;
  final String? dateDecisionIso;

  /// nbPlaces x price per seat, in centimes.
  final int montantCentimes;

  /// Set once the passenger confirmed boarding (QR code or Bluetooth).
  final String? embarqueLeIso;
  final BoardingMethod? embarqueMethode;

  bool get estEmbarque => embarqueLeIso != null;

  factory TripReservationDto.fromJson(Map<String, dynamic> json) => TripReservationDto(
        id: json['id'] as int,
        trajet: TripDto.fromJson(json['trajet'] as Map<String, dynamic>),
        passagerId: json['passager_id'] as int,
        passagerNom: json['passager_nom'] as String,
        passagerPhoto: json['passager_photo'] as String?,
        nbPlaces: json['nb_places'] as int,
        statut: TripReservationStatus.parse(json['statut'] as String),
        dateReservationIso: json['date_reservation'] as String,
        dateDecisionIso: json['date_decision'] as String?,
        montantCentimes: json['montant_centimes'] as int,
        embarqueLeIso: json['embarque_le'] as String?,
        embarqueMethode: json['embarque_methode'] == null
            ? null
            : BoardingMethod.parse(json['embarque_methode'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trajet': trajet.toJson(),
        'passager_id': passagerId,
        'passager_nom': passagerNom,
        'passager_photo': passagerPhoto,
        'nb_places': nbPlaces,
        'statut': statut.apiValue,
        'date_reservation': dateReservationIso,
        'date_decision': dateDecisionIso,
        'montant_centimes': montantCentimes,
        'embarque_le': embarqueLeIso,
        'embarque_methode': embarqueMethode?.apiValue,
      };
}

/// How the passenger proved he was in the vehicle.
enum BoardingMethod {
  qr('qr'),
  bluetooth('bluetooth');

  const BoardingMethod(this.apiValue);
  final String apiValue;

  static BoardingMethod? tryParse(String value) {
    for (final m in values) {
      if (m.apiValue == value) return m;
    }
    return null;
  }

  static BoardingMethod parse(String value) =>
      tryParse(value) ?? BoardingMethod.qr;
}

/// Short-lived code shown by the driver (QR code or Bluetooth broadcast).
/// [payload] is what the QR code encodes; it must be refreshed before
/// [expiresInSeconds] runs out.
class BoardingCodeDto {
  const BoardingCodeDto({
    required this.tripId,
    required this.code,
    required this.payload,
    required this.expiresInSeconds,
    required this.stepSeconds,
  });

  final int tripId;
  final String code;
  final String payload;
  final int expiresInSeconds;
  final int stepSeconds;

  /// Extracts the code from a scanned QR payload for [expectedTripId]
  /// (null when it is not a ProxiLife boarding QR or targets another trip).
  static String? codeFromPayload(String payload, int expectedTripId) {
    final parts = payload.trim().split(':');
    if (parts.length != 4 || parts[0] != 'proxilife' || parts[1] != 'board') {
      return null;
    }
    if (int.tryParse(parts[2]) != expectedTripId) return null;
    return parts[3];
  }

  factory BoardingCodeDto.fromJson(Map<String, dynamic> json) =>
      BoardingCodeDto(
        tripId: json['trajet_id'] as int,
        code: json['code'] as String,
        payload: json['payload'] as String,
        expiresInSeconds: json['expire_dans_s'] as int,
        stepSeconds: json['pas_s'] as int,
      );

  Map<String, dynamic> toJson() => {
        'trajet_id': tripId,
        'code': code,
        'payload': payload,
        'expire_dans_s': expiresInSeconds,
        'pas_s': stepSeconds,
      };
}
