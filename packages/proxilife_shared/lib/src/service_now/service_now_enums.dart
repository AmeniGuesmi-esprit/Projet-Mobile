/// ServiceNow (services à domicile) enumerations, same pattern as
/// `../enums.dart`: [apiValue] is the snake_case value stored in SQLite and
/// sent over HTTP, [label] is the French text shown in the app.
library;

/// Kind of work requested by the client.
enum ServiceNowType {
  plomberie('plomberie', 'Plomberie'),
  electricite('electricite', 'Électricité'),
  menage('menage', 'Ménage'),
  jardinage('jardinage', 'Jardinage'),
  bricolage('bricolage', 'Bricolage'),
  climatisation('climatisation', 'Climatisation'),
  peinture('peinture', 'Peinture'),
  autre('autre', 'Autre');

  const ServiceNowType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ServiceNowType? tryParse(String value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }

  static ServiceNowType parse(String value) =>
      tryParse(value) ??
      (throw ArgumentError('Type de service inconnu : $value'));
}

/// The two photos a prestataire can attach to an intervention.
enum InterventionPhotoKind {
  avant('avant', 'Avant'),
  apres('apres', 'Après');

  const InterventionPhotoKind(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static InterventionPhotoKind parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Photo inconnue : $value'));
}

/// Lifecycle of a [DemandeServiceDto] (see `ServiceNowRules`).
enum DemandeServiceStatus {
  enAttente('en_attente', 'En attente'),
  acceptee('acceptee', 'Acceptée'),
  enCours('en_cours', 'En cours'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const DemandeServiceStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DemandeServiceStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de demande inconnu : $value'));
}

/// Lifecycle of an [InterventionDto] (see `ServiceNowRules`).
enum InterventionStatus {
  planifiee('planifiee', 'Planifiée'),
  enCours('en_cours', 'En cours'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const InterventionStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static InterventionStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut d\'intervention inconnu : $value'));
}
