import '../enums.dart';
import 'foodsave_enums.dart';

// All FoodSave timestamps travel as UTC ISO-8601 strings ("...Z").
// Parse with [_date]; the app converts with `.toLocal()` for display.

DateTime _date(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
String _iso(DateTime d) => d.toUtc().toIso8601String();
double? _doubleOrNull(Object? v) => v == null ? null : (v as num).toDouble();

/// A merchant's store (commerce) with its GPS position.
class StoreDto {
  const StoreDto({
    required this.id,
    required this.commercantId,
    required this.nom,
    required this.adresse,
    required this.latitude,
    required this.longitude,
    required this.categorie,
  });

  final int id;
  final int commercantId;
  final String nom;
  final String adresse;
  final double latitude;
  final double longitude;
  final FoodCategory categorie;

  factory StoreDto.fromJson(Map<String, dynamic> json) => StoreDto(
        id: json['id'] as int,
        commercantId: json['commercant_id'] as int,
        nom: json['nom'] as String,
        adresse: json['adresse'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        categorie: FoodCategory.parse(json['categorie'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'commercant_id': commercantId,
        'nom': nom,
        'adresse': adresse,
        'latitude': latitude,
        'longitude': longitude,
        'categorie': categorie.apiValue,
      };
}

/// An anti-waste basket. [quantite] is the number of units still on sale.
class BasketDto {
  const BasketDto({
    required this.id,
    required this.titre,
    required this.contenu,
    required this.categorie,
    required this.prixCentimes,
    required this.prixInitialCentimes,
    required this.quantite,
    required this.quantiteInitiale,
    required this.creneauRetraitDebut,
    required this.creneauRetraitFin,
    required this.dateExpiration,
    required this.statut,
    required this.commercantId,
    required this.creeLe,
    this.image,
    this.commerce,
    this.distanceKm,
    this.reservationsActives,
  });

  final int id;
  final String titre;
  final String contenu;
  final FoodCategory categorie;

  /// Server-side file name; fetch with `GET /foodsave/images/<image>`.
  final String? image;
  final int prixCentimes;
  final int prixInitialCentimes;
  final int quantite;
  final int quantiteInitiale;
  final DateTime creneauRetraitDebut;
  final DateTime creneauRetraitFin;
  final DateTime dateExpiration;
  final BasketStatus statut;
  final int commercantId;
  final DateTime creeLe;

  /// Embedded store (always present in client listings).
  final StoreDto? commerce;

  /// Distance from the client's position, when known.
  final double? distanceKm;

  /// Active (en_attente) reservations — merchant views only.
  final int? reservationsActives;

  factory BasketDto.fromJson(Map<String, dynamic> json) => BasketDto(
        id: json['id'] as int,
        titre: json['titre'] as String,
        contenu: json['contenu'] as String,
        categorie: FoodCategory.parse(json['categorie'] as String),
        image: json['image'] as String?,
        prixCentimes: json['prix_centimes'] as int,
        prixInitialCentimes: json['prix_initial_centimes'] as int,
        quantite: json['quantite'] as int,
        quantiteInitiale: json['quantite_initiale'] as int,
        creneauRetraitDebut: _date(json['creneau_retrait_debut']),
        creneauRetraitFin: _date(json['creneau_retrait_fin']),
        dateExpiration: _date(json['date_expiration']),
        statut: BasketStatus.parse(json['statut'] as String),
        commercantId: json['commercant_id'] as int,
        creeLe: _date(json['cree_le']),
        commerce: json['commerce'] == null
            ? null
            : StoreDto.fromJson(json['commerce'] as Map<String, dynamic>),
        distanceKm: _doubleOrNull(json['distance_km']),
        reservationsActives: json['reservations_actives'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'contenu': contenu,
        'categorie': categorie.apiValue,
        'image': image,
        'prix_centimes': prixCentimes,
        'prix_initial_centimes': prixInitialCentimes,
        'quantite': quantite,
        'quantite_initiale': quantiteInitiale,
        'creneau_retrait_debut': _iso(creneauRetraitDebut),
        'creneau_retrait_fin': _iso(creneauRetraitFin),
        'date_expiration': _iso(dateExpiration),
        'statut': statut.apiValue,
        'commercant_id': commercantId,
        'cree_le': _iso(creeLe),
        'commerce': commerce?.toJson(),
        'distance_km': distanceKm,
        'reservations_actives': reservationsActives,
      };
}

/// A client's reservation. [statut] (pickup lifecycle) and [statutPaiement]
/// (linked payment transaction) are independent.
class ReservationDto {
  const ReservationDto({
    required this.id,
    required this.date,
    required this.statut,
    required this.panierId,
    required this.clientId,
    required this.quantiteReservee,
    required this.montantCentimes,
    required this.statutPaiement,
    this.modePaiement,
    this.moyenPaiementId,
    this.transactionId,
    this.factureNumero,
    this.dateCreationQr,
    this.dateExpirationQr,
    this.qrToken,
    this.retireLe,
    this.panier,
    this.clientNom,
  });

  final int id;
  final DateTime date;
  final ReservationStatus statut;
  final int panierId;
  final int clientId;
  final int quantiteReservee;
  final int montantCentimes;
  final PaymentMethodType? modePaiement;
  final int? moyenPaiementId;
  final TransactionStatus statutPaiement;
  final int? transactionId;
  final String? factureNumero;
  final DateTime? dateCreationQr;
  final DateTime? dateExpirationQr;

  /// Opaque QR payload — only returned to the owning client while the
  /// reservation is active and paid. Never contains personal data.
  final String? qrToken;
  final DateTime? retireLe;

  /// Basket summary (with its store) for display.
  final BasketDto? panier;

  /// "Prénom N." — merchant views only.
  final String? clientNom;

  factory ReservationDto.fromJson(Map<String, dynamic> json) => ReservationDto(
        id: json['id'] as int,
        date: _date(json['date']),
        statut: ReservationStatus.parse(json['statut'] as String),
        panierId: json['panier_id'] as int,
        clientId: json['client_id'] as int,
        quantiteReservee: json['quantite_reservee'] as int,
        montantCentimes: json['montant_centimes'] as int,
        modePaiement: json['mode_paiement'] == null
            ? null
            : PaymentMethodType.parse(json['mode_paiement'] as String),
        moyenPaiementId: json['moyen_paiement_id'] as int?,
        statutPaiement:
            TransactionStatus.parse(json['statut_paiement'] as String),
        transactionId: json['transaction_id'] as int?,
        factureNumero: json['facture_numero'] as String?,
        dateCreationQr: _dateOrNull(json['date_creation_qr']),
        dateExpirationQr: _dateOrNull(json['date_expiration_qr']),
        qrToken: json['qr_token'] as String?,
        retireLe: _dateOrNull(json['retire_le']),
        panier: json['panier'] == null
            ? null
            : BasketDto.fromJson(json['panier'] as Map<String, dynamic>),
        clientNom: json['client_nom'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _iso(date),
        'statut': statut.apiValue,
        'panier_id': panierId,
        'client_id': clientId,
        'quantite_reservee': quantiteReservee,
        'montant_centimes': montantCentimes,
        'mode_paiement': modePaiement?.apiValue,
        'moyen_paiement_id': moyenPaiementId,
        'statut_paiement': statutPaiement.apiValue,
        'transaction_id': transactionId,
        'facture_numero': factureNumero,
        'date_creation_qr':
            dateCreationQr == null ? null : _iso(dateCreationQr!),
        'date_expiration_qr':
            dateExpirationQr == null ? null : _iso(dateExpirationQr!),
        'qr_token': qrToken,
        'retire_le': retireLe == null ? null : _iso(retireLe!),
        'panier': panier?.toJson(),
        'client_nom': clientNom,
      };
}

/// In-app notification (polled by the app, shown as a local notification).
class FoodSaveNotificationDto {
  const FoodSaveNotificationDto({
    required this.id,
    required this.type,
    required this.titre,
    required this.message,
    required this.lu,
    required this.creeLe,
    this.panierId,
    this.reservationId,
  });

  final int id;
  final FoodSaveNotificationType type;
  final String titre;
  final String message;
  final int? panierId;
  final int? reservationId;
  final bool lu;
  final DateTime creeLe;

  factory FoodSaveNotificationDto.fromJson(Map<String, dynamic> json) =>
      FoodSaveNotificationDto(
        id: json['id'] as int,
        type: FoodSaveNotificationType.parse(json['type'] as String),
        titre: json['titre'] as String,
        message: json['message'] as String,
        panierId: json['panier_id'] as int?,
        reservationId: json['reservation_id'] as int?,
        lu: json['lu'] as bool,
        creeLe: _date(json['cree_le']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.apiValue,
        'titre': titre,
        'message': message,
        'panier_id': panierId,
        'reservation_id': reservationId,
        'lu': lu,
        'cree_le': _iso(creeLe),
      };
}

/// Result of `POST /foodsave/merchant/scan`.
class ScanResultDto {
  const ScanResultDto({
    required this.resultat,
    required this.message,
    this.reservation,
  });

  final ScanOutcome resultat;

  /// French, user-facing explanation (why it was refused, or what to hand over).
  final String message;
  final ReservationDto? reservation;

  bool get accepte => resultat == ScanOutcome.accepte;

  factory ScanResultDto.fromJson(Map<String, dynamic> json) => ScanResultDto(
        resultat: ScanOutcome.parse(json['resultat'] as String),
        message: json['message'] as String,
        reservation: json['reservation'] == null
            ? null
            : ReservationDto.fromJson(
                json['reservation'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'resultat': resultat.apiValue,
        'message': message,
        'reservation': reservation?.toJson(),
      };
}

/// One day of merchant activity (for dashboard charts).
class DailyStatDto {
  const DailyStatDto({
    required this.date,
    required this.reservations,
    required this.retraits,
    required this.revenusCentimes,
  });

  /// `YYYY-MM-DD` (UTC day).
  final String date;
  final int reservations;
  final int retraits;
  final int revenusCentimes;

  factory DailyStatDto.fromJson(Map<String, dynamic> json) => DailyStatDto(
        date: json['date'] as String,
        reservations: json['reservations'] as int,
        retraits: json['retraits'] as int,
        revenusCentimes: json['revenus_centimes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'reservations': reservations,
        'retraits': retraits,
        'revenus_centimes': revenusCentimes,
      };
}

/// Merchant dashboard aggregates (`GET /foodsave/merchant/stats`).
class MerchantStatsDto {
  const MerchantStatsDto({
    required this.paniersActifs,
    required this.reservationsEnAttente,
    required this.retraitsTotal,
    required this.repasSauves,
    required this.revenusCentimes,
    required this.tauxRetrait,
    required this.parJour,
    required this.parStatut,
  });

  final int paniersActifs;
  final int reservationsEnAttente;
  final int retraitsTotal;

  /// Units actually picked up (meals saved from waste).
  final int repasSauves;
  final int revenusCentimes;

  /// Picked-up / (picked-up + expired), 0–100.
  final int tauxRetrait;

  /// Last 7 days, oldest first, always 7 entries.
  final List<DailyStatDto> parJour;

  /// Reservation counts keyed by [ReservationStatus.apiValue].
  final Map<String, int> parStatut;

  factory MerchantStatsDto.fromJson(Map<String, dynamic> json) =>
      MerchantStatsDto(
        paniersActifs: json['paniers_actifs'] as int,
        reservationsEnAttente: json['reservations_en_attente'] as int,
        retraitsTotal: json['retraits_total'] as int,
        repasSauves: json['repas_sauves'] as int,
        revenusCentimes: json['revenus_centimes'] as int,
        tauxRetrait: json['taux_retrait'] as int,
        parJour: (json['par_jour'] as List)
            .map((e) => DailyStatDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        parStatut: (json['par_statut'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int)),
      );

  Map<String, dynamic> toJson() => {
        'paniers_actifs': paniersActifs,
        'reservations_en_attente': reservationsEnAttente,
        'retraits_total': retraitsTotal,
        'repas_sauves': repasSauves,
        'revenus_centimes': revenusCentimes,
        'taux_retrait': tauxRetrait,
        'par_jour': parJour.map((d) => d.toJson()).toList(),
        'par_statut': parStatut,
      };
}
