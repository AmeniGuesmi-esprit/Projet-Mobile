import 'package:proxilife_shared/proxilife_shared.dart';

/// Row → DTO mappers shared by all FoodSave services (single source of truth
/// for column names).

StoreDto storeFromRow(Map<String, Object?> row) => StoreDto(
      id: row['id'] as int,
      commercantId: row['commercant_id'] as int,
      nom: row['nom'] as String,
      adresse: row['adresse'] as String,
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      categorie: FoodCategory.parse(row['categorie'] as String),
    );

/// [store] / [distanceKm] / [reservationsActives] are optional enrichments.
BasketDto basketFromRow(
  Map<String, Object?> row, {
  StoreDto? store,
  double? distanceKm,
  int? reservationsActives,
}) =>
    BasketDto(
      id: row['id'] as int,
      titre: row['titre'] as String,
      contenu: row['contenu'] as String,
      categorie: FoodCategory.parse(row['categorie'] as String),
      image: row['image'] as String?,
      prixCentimes: row['prix_centimes'] as int,
      prixInitialCentimes: row['prix_initial_centimes'] as int,
      quantite: row['quantite'] as int,
      quantiteInitiale: row['quantite_initiale'] as int,
      creneauRetraitDebut: DateTime.parse(row['creneau_retrait_debut'] as String),
      creneauRetraitFin: DateTime.parse(row['creneau_retrait_fin'] as String),
      dateExpiration: DateTime.parse(row['date_expiration'] as String),
      statut: BasketStatus.parse(row['statut'] as String),
      commercantId: row['commercant_id'] as int,
      creeLe: DateTime.parse(row['cree_le'] as String),
      dureeReservationMinutes: row['duree_reservation_minutes'] as int? ??
          foodSaveDefaultReservationMinutes,
      commerce: store,
      distanceKm: distanceKm,
      reservationsActives: reservationsActives,
    );

/// [qrToken] must only be passed for the owning client of an active, paid
/// reservation. [clientNom] only for merchant views ("Prénom N.").
ReservationDto reservationFromRow(
  Map<String, Object?> row, {
  BasketDto? panier,
  String? qrToken,
  String? clientNom,
  String? factureNumero,
}) =>
    ReservationDto(
      id: row['id'] as int,
      date: DateTime.parse(row['date'] as String),
      statut: ReservationStatus.parse(row['statut'] as String),
      panierId: row['panier_id'] as int,
      clientId: row['client_id'] as int,
      quantiteReservee: row['quantite_reservee'] as int,
      montantCentimes: row['montant_centimes'] as int,
      modePaiement: row['mode_paiement'] == null
          ? null
          : PaymentMethodType.parse(row['mode_paiement'] as String),
      moyenPaiementId: row['moyen_paiement_id'] as int?,
      statutPaiement: TransactionStatus.parse(row['statut_paiement'] as String),
      transactionId: row['transaction_id'] as int?,
      factureNumero: factureNumero,
      dateCreationQr: row['date_creation_qr'] == null
          ? null
          : DateTime.parse(row['date_creation_qr'] as String),
      dateExpirationQr: row['date_expiration_qr'] == null
          ? null
          : DateTime.parse(row['date_expiration_qr'] as String),
      qrToken: qrToken,
      retireLe: row['retire_le'] == null
          ? null
          : DateTime.parse(row['retire_le'] as String),
      panier: panier,
      clientNom: clientNom,
    );

/// "Ameni G." — never expose full names / e-mails to merchants.
String shortName(String prenom, String nom) =>
    nom.isEmpty ? prenom : '$prenom ${nom.substring(0, 1).toUpperCase()}.';
