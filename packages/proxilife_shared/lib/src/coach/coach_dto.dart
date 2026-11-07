import '../enums.dart';
import 'coach_enums.dart';

DateTime _utc(Object? raw) => DateTime.parse(raw as String).toUtc();

double? _double(Object? raw) => raw == null ? null : (raw as num).toDouble();

/// A sport session published by a coach (entity "Séance").
class CoachSessionDto {
  const CoachSessionDto({
    required this.id,
    required this.type,
    required this.titre,
    this.description,
    required this.lieu,
    required this.latitude,
    required this.longitude,
    required this.dateHeure,
    required this.dureeMinutes,
    required this.niveau,
    required this.placesTotales,
    required this.placesRestantes,
    required this.prixCentimes,
    required this.statut,
    required this.coachId,
    required this.coachNom,
    this.distanceKm,
    this.dejaReserve = false,
  });

  final int id;
  final CoachSessionType type;
  final String titre;
  final String? description;

  /// Human-readable address of the venue.
  final String lieu;
  final double latitude;
  final double longitude;

  /// Start of the session (UTC).
  final DateTime dateHeure;
  final int dureeMinutes;
  final CoachLevel niveau;
  final int placesTotales;
  final int placesRestantes;

  /// Price per participant, whole cents (0 = free).
  final int prixCentimes;
  final CoachSessionStatus statut;
  final int coachId;
  final String coachNom;

  /// Distance from the position sent by the client (search only).
  final double? distanceKm;

  /// The viewer already holds an active booking on this session.
  final bool dejaReserve;

  DateTime get fin => dateHeure.add(Duration(minutes: dureeMinutes));
  int get inscrits => placesTotales - placesRestantes;
  bool get isFull => placesRestantes <= 0;
  bool get isFree => prixCentimes == 0;
  bool get isCancelled => statut == CoachSessionStatus.annulee;

  factory CoachSessionDto.fromJson(Map<String, dynamic> json) =>
      CoachSessionDto(
        id: json['id'] as int,
        type: CoachSessionType.parse(json['type'] as String),
        titre: json['titre'] as String,
        description: json['description'] as String?,
        lieu: json['lieu'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        dateHeure: _utc(json['date_heure']),
        dureeMinutes: json['duree_minutes'] as int,
        niveau: CoachLevel.parse(json['niveau'] as String),
        placesTotales: json['places_totales'] as int,
        placesRestantes: json['places_restantes'] as int,
        prixCentimes: json['prix_centimes'] as int,
        statut: CoachSessionStatus.parse(json['statut'] as String),
        coachId: json['coach_id'] as int,
        coachNom: json['coach_nom'] as String,
        distanceKm: _double(json['distance_km']),
        dejaReserve: json['deja_reserve'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.apiValue,
        'titre': titre,
        'description': description,
        'lieu': lieu,
        'latitude': latitude,
        'longitude': longitude,
        'date_heure': dateHeure.toUtc().toIso8601String(),
        'duree_minutes': dureeMinutes,
        'niveau': niveau.apiValue,
        'places_totales': placesTotales,
        'places_restantes': placesRestantes,
        'prix_centimes': prixCentimes,
        'statut': statut.apiValue,
        'coach_id': coachId,
        'coach_nom': coachNom,
        'distance_km': distanceKm,
        'deja_reserve': dejaReserve,
      };
}

/// A booking of a session by a client (entity "Réservation").
class CoachBookingDto {
  const CoachBookingDto({
    required this.id,
    required this.statut,
    required this.seanceId,
    this.seance,
    required this.clientId,
    required this.clientNom,
    this.codeQr,
    required this.montantCentimes,
    this.modePaiement,
    this.statutPaiement,
    this.factureNumero,
    this.pas,
    this.distanceKm,
    this.frequenceCardiaque,
    this.presentLe,
    required this.creeLe,
  });

  final int id;
  final CoachBookingStatus statut;
  final int seanceId;

  /// The booked session (always set by the server).
  final CoachSessionDto? seance;
  final int clientId;
  final String clientNom;

  /// QR payload to show to the coach. Only sent to the booking's owner while
  /// the booking is active; `null` otherwise.
  final String? codeQr;
  final int montantCentimes;
  final PaymentMethodType? modePaiement;
  final TransactionStatus? statutPaiement;
  final String? factureNumero;

  /// Tracking data entered / read during the session.
  final int? pas;
  final double? distanceKm;
  final int? frequenceCardiaque;
  final DateTime? presentLe;
  final DateTime creeLe;

  bool get hasQr => codeQr != null && codeQr!.isNotEmpty;

  factory CoachBookingDto.fromJson(Map<String, dynamic> json) =>
      CoachBookingDto(
        id: json['id'] as int,
        statut: CoachBookingStatus.parse(json['statut'] as String),
        seanceId: json['seance_id'] as int,
        seance: json['seance'] == null
            ? null
            : CoachSessionDto.fromJson(json['seance'] as Map<String, dynamic>),
        clientId: json['client_id'] as int,
        clientNom: json['client_nom'] as String,
        codeQr: json['code_qr'] as String?,
        montantCentimes: json['montant_centimes'] as int,
        modePaiement: json['mode_paiement'] == null
            ? null
            : PaymentMethodType.parse(json['mode_paiement'] as String),
        statutPaiement: json['statut_paiement'] == null
            ? null
            : TransactionStatus.parse(json['statut_paiement'] as String),
        factureNumero: json['facture_numero'] as String?,
        pas: json['pas'] as int?,
        distanceKm: _double(json['distance_km']),
        frequenceCardiaque: json['frequence_cardiaque'] as int?,
        presentLe:
            json['present_le'] == null ? null : _utc(json['present_le']),
        creeLe: _utc(json['cree_le']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'statut': statut.apiValue,
        'seance_id': seanceId,
        'seance': seance?.toJson(),
        'client_id': clientId,
        'client_nom': clientNom,
        'code_qr': codeQr,
        'montant_centimes': montantCentimes,
        'mode_paiement': modePaiement?.apiValue,
        'statut_paiement': statutPaiement?.apiValue,
        'facture_numero': factureNumero,
        'pas': pas,
        'distance_km': distanceKm,
        'frequence_cardiaque': frequenceCardiaque,
        'present_le': presentLe?.toUtc().toIso8601String(),
        'cree_le': creeLe.toUtc().toIso8601String(),
      };
}

/// Outcome of a presence scan, shown to the coach.
class CoachScanResultDto {
  const CoachScanResultDto({
    required this.reservation,
    required this.dejaPresent,
    required this.especesEncaissees,
  });

  final CoachBookingDto reservation;

  /// The presence had already been validated (nothing changed).
  final bool dejaPresent;

  /// A cash payment was confirmed by this scan.
  final bool especesEncaissees;

  factory CoachScanResultDto.fromJson(Map<String, dynamic> json) =>
      CoachScanResultDto(
        reservation: CoachBookingDto.fromJson(
            json['reservation'] as Map<String, dynamic>),
        dejaPresent: json['deja_present'] as bool? ?? false,
        especesEncaissees: json['especes_encaissees'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'reservation': reservation.toJson(),
        'deja_present': dejaPresent,
        'especes_encaissees': especesEncaissees,
      };
}

/// In-app notification (confirmation, reminder, cancellation...).
class CoachNotificationDto {
  const CoachNotificationDto({
    required this.id,
    required this.type,
    required this.titre,
    required this.message,
    this.seanceId,
    this.reservationId,
    required this.lu,
    required this.creeLe,
  });

  final int id;
  final CoachNotificationType type;
  final String titre;
  final String message;
  final int? seanceId;
  final int? reservationId;
  final bool lu;
  final DateTime creeLe;

  factory CoachNotificationDto.fromJson(Map<String, dynamic> json) =>
      CoachNotificationDto(
        id: json['id'] as int,
        type: CoachNotificationType.parse(json['type'] as String),
        titre: json['titre'] as String,
        message: json['message'] as String,
        seanceId: json['seance_id'] as int?,
        reservationId: json['reservation_id'] as int?,
        lu: json['lu'] as bool,
        creeLe: _utc(json['cree_le']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.apiValue,
        'titre': titre,
        'message': message,
        'seance_id': seanceId,
        'reservation_id': reservationId,
        'lu': lu,
        'cree_le': creeLe.toUtc().toIso8601String(),
      };
}
