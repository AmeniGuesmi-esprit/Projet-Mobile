/// FoodSave (anti-gaspillage) enumerations shared by the app and the server.
///
/// Same convention as `enums.dart`: [apiValue] is the snake_case string
/// stored in the database and exchanged over HTTP.
library;

/// Lifecycle of a basket (panier).
enum BasketStatus {
  disponible('disponible'),
  epuise('epuise'),
  expire('expire'),
  annule('annule');

  const BasketStatus(this.apiValue);
  final String apiValue;

  static BasketStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Statut de panier inconnu : $value'));

  String get label => switch (this) {
        BasketStatus.disponible => 'Disponible',
        BasketStatus.epuise => 'Épuisé',
        BasketStatus.expire => 'Expiré',
        BasketStatus.annule => 'Annulé',
      };
}

/// Lifecycle of a reservation. Payment status is tracked separately with
/// [TransactionStatus] (the linked payment transaction).
enum ReservationStatus {
  enAttente('en_attente'),
  retire('retire'),
  expire('expire'),
  annule('annule');

  const ReservationStatus(this.apiValue);
  final String apiValue;

  static ReservationStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de réservation inconnu : $value'));

  String get label => switch (this) {
        ReservationStatus.enAttente => 'À retirer',
        ReservationStatus.retire => 'Retiré',
        ReservationStatus.expire => 'Expiré',
        ReservationStatus.annule => 'Annulé',
      };
}

/// Food category of a basket / store.
enum FoodCategory {
  boulangerie('boulangerie'),
  fruitsLegumes('fruits_legumes'),
  platsPrepares('plats_prepares'),
  epicerie('epicerie'),
  produitsLaitiers('produits_laitiers'),
  patisserie('patisserie'),
  mixte('mixte');

  const FoodCategory(this.apiValue);
  final String apiValue;

  static FoodCategory parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Catégorie inconnue : $value'));

  String get label => switch (this) {
        FoodCategory.boulangerie => 'Boulangerie',
        FoodCategory.fruitsLegumes => 'Fruits & légumes',
        FoodCategory.platsPrepares => 'Plats préparés',
        FoodCategory.epicerie => 'Épicerie',
        FoodCategory.produitsLaitiers => 'Produits laitiers',
        FoodCategory.patisserie => 'Pâtisserie',
        FoodCategory.mixte => 'Panier mixte',
      };
}

/// Kinds of in-app FoodSave notifications (delivered by polling, see
/// `GET /foodsave/notifications`).
enum FoodSaveNotificationType {
  nouveauPanier('nouveau_panier'),
  reservationConfirmee('reservation_confirmee'),
  qrExpireBientot('qr_expire_bientot'),
  reservationExpiree('reservation_expiree'),
  panierAnnule('panier_annule'),
  retraitEffectue('retrait_effectue');

  const FoodSaveNotificationType(this.apiValue);
  final String apiValue;

  static FoodSaveNotificationType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Type de notification inconnu : $value'));
}

/// Outcome of a merchant QR scan.
enum ScanOutcome {
  accepte('accepte'),
  expire('expire'),
  dejaUtilise('deja_utilise'),
  annule('annule'),
  invalide('invalide'),
  autreCommercant('autre_commercant'),
  paiementNonConfirme('paiement_non_confirme');

  const ScanOutcome(this.apiValue);
  final String apiValue;

  static ScanOutcome parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Résultat de scan inconnu : $value'));
}

/// Sort order for the client basket list.
enum BasketSort {
  distance('distance'),
  prix('prix'),
  reduction('reduction');

  const BasketSort(this.apiValue);
  final String apiValue;

  static BasketSort parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Tri inconnu : $value'));
}
