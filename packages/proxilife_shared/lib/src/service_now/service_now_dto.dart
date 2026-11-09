import '../enums.dart';
import 'service_now_enums.dart';

/// The work carried out by a prestataire for a [DemandeServiceDto].
/// Dates are UTC on the wire; call `toLocal()` to display them.
class InterventionDto {
  const InterventionDto({
    required this.id,
    required this.demandeId,
    required this.datePrevue,
    required this.prixCentimes,
    required this.statut,
    this.prestataireId,
    this.prestataireNom,
    this.prestataireTelephone,
    this.dateDebut,
    this.dateFin,
    this.rapport,
    this.transactionId,
    this.paiementStatut,
    this.qrCode,
    this.enRouteLe,
    this.aPhotoAvant = false,
    this.aPhotoApres = false,
    this.note,
    this.commentaire,
    this.prestataireNoteMoyenne,
    this.prestataireNbNotes = 0,
  });

  final int id;
  final int demandeId;

  /// Null once the prestataire has deleted his account.
  final int? prestataireId;
  final String? prestataireNom;

  /// Only sent to the people involved in the intervention.
  final String? prestataireTelephone;
  final DateTime datePrevue;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final String? rapport;
  final int prixCentimes;
  final InterventionStatus statut;

  /// Payment module transaction, set once the client has paid.
  final int? transactionId;

  /// Live status of [transactionId] (null when nothing has been paid).
  final TransactionStatus? paiementStatut;

  /// Proof-of-presence code. Only sent to the client, before the work starts.
  final String? qrCode;

  /// When the prestataire left; null until he shares his position.
  final DateTime? enRouteLe;
  final bool aPhotoAvant;
  final bool aPhotoApres;

  /// The client's rating (1 to 5), once given.
  final int? note;
  final String? commentaire;

  /// The prestataire's average over all his rated interventions.
  final double? prestataireNoteMoyenne;
  final int prestataireNbNotes;

  bool get estPayee => paiementStatut == TransactionStatus.paye;

  factory InterventionDto.fromJson(Map<String, dynamic> json) =>
      InterventionDto(
        id: json['id'] as int,
        demandeId: json['demande_id'] as int,
        prestataireId: json['prestataire_id'] as int?,
        prestataireNom: json['prestataire_nom'] as String?,
        prestataireTelephone: json['prestataire_telephone'] as String?,
        datePrevue: DateTime.parse(json['date_prevue'] as String),
        dateDebut: _optionalDate(json['date_debut']),
        dateFin: _optionalDate(json['date_fin']),
        rapport: json['rapport'] as String?,
        prixCentimes: json['prix_centimes'] as int,
        statut: InterventionStatus.parse(json['statut'] as String),
        transactionId: json['transaction_id'] as int?,
        paiementStatut: json['paiement_statut'] == null
            ? null
            : TransactionStatus.parse(json['paiement_statut'] as String),
        qrCode: json['qr_code'] as String?,
        enRouteLe: _optionalDate(json['en_route_le']),
        aPhotoAvant: json['a_photo_avant'] as bool? ?? false,
        aPhotoApres: json['a_photo_apres'] as bool? ?? false,
        note: json['note'] as int?,
        commentaire: json['commentaire'] as String?,
        prestataireNoteMoyenne:
            (json['prestataire_note_moyenne'] as num?)?.toDouble(),
        prestataireNbNotes: json['prestataire_nb_notes'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'demande_id': demandeId,
        'prestataire_id': prestataireId,
        'prestataire_nom': prestataireNom,
        'prestataire_telephone': prestataireTelephone,
        'date_prevue': _utc(datePrevue),
        'date_debut': dateDebut == null ? null : _utc(dateDebut!),
        'date_fin': dateFin == null ? null : _utc(dateFin!),
        'rapport': rapport,
        'prix_centimes': prixCentimes,
        'statut': statut.apiValue,
        'transaction_id': transactionId,
        'paiement_statut': paiementStatut?.apiValue,
        'qr_code': qrCode,
        'en_route_le': enRouteLe == null ? null : _utc(enRouteLe!),
        'a_photo_avant': aPhotoAvant,
        'a_photo_apres': aPhotoApres,
        'note': note,
        'commentaire': commentaire,
        'prestataire_note_moyenne': prestataireNoteMoyenne,
        'prestataire_nb_notes': prestataireNbNotes,
      };
}

/// A home-service request created by a client.
class DemandeServiceDto {
  const DemandeServiceDto({
    required this.id,
    required this.clientId,
    required this.clientNom,
    required this.type,
    required this.description,
    required this.adresse,
    required this.dateSouhaitee,
    required this.statut,
    required this.creeLe,
    required this.modifieLe,
    this.clientTelephone,
    this.intervention,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.specialiteCorrespond = false,
    this.disponibleALaDate = true,
  });

  final int id;
  final int clientId;
  final String clientNom;

  /// Only sent once a prestataire is committed to the request.
  final String? clientTelephone;
  final ServiceNowType type;
  final String description;
  final String adresse;
  final DateTime dateSouhaitee;
  final DemandeServiceStatus statut;
  final DateTime creeLe;
  final DateTime modifieLe;

  /// Latest intervention; null while the request waits for a prestataire.
  final InterventionDto? intervention;

  /// Set when the address was located on the map.
  final double? latitude;
  final double? longitude;

  /// Distance from the prestataire viewing the list.
  final double? distanceKm;

  /// True when the request matches one of the prestataire's specialties.
  final bool specialiteCorrespond;

  /// False when the wanted date is outside the prestataire's calendar.
  final bool disponibleALaDate;

  factory DemandeServiceDto.fromJson(Map<String, dynamic> json) =>
      DemandeServiceDto(
        id: json['id'] as int,
        clientId: json['client_id'] as int,
        clientNom: json['client_nom'] as String,
        clientTelephone: json['client_telephone'] as String?,
        type: ServiceNowType.parse(json['type'] as String),
        description: json['description'] as String,
        adresse: json['adresse'] as String,
        dateSouhaitee: DateTime.parse(json['date_souhaitee'] as String),
        statut: DemandeServiceStatus.parse(json['statut'] as String),
        creeLe: DateTime.parse(json['cree_le'] as String),
        modifieLe: DateTime.parse(json['modifie_le'] as String),
        intervention: json['intervention'] == null
            ? null
            : InterventionDto.fromJson(
                json['intervention'] as Map<String, dynamic>),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        specialiteCorrespond: json['specialite_correspond'] as bool? ?? false,
        disponibleALaDate: json['disponible_a_la_date'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'client_nom': clientNom,
        'client_telephone': clientTelephone,
        'type': type.apiValue,
        'description': description,
        'adresse': adresse,
        'date_souhaitee': _utc(dateSouhaitee),
        'statut': statut.apiValue,
        'cree_le': _utc(creeLe),
        'modifie_le': _utc(modifieLe),
        'intervention': intervention?.toJson(),
        'latitude': latitude,
        'longitude': longitude,
        'distance_km': distanceKm,
        'specialite_correspond': specialiteCorrespond,
        'disponible_a_la_date': disponibleALaDate,
      };
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

String _utc(DateTime value) => value.toUtc().toIso8601String();
