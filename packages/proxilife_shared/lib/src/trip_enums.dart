/// Enumerations of the carpooling (covoiturage) module, shared by the app and
/// the server. Same conventions as `enums.dart`: [apiValue] is the snake_case
/// string stored in the database and sent over HTTP.
library;

/// Ambiance souhaitée pendant le trajet.
enum Ambiance {
  discussion('discussion'),
  silence('silence'),
  indifferent('indifferent');

  const Ambiance(this.apiValue);
  final String apiValue;

  static Ambiance parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Ambiance inconnue : $value'));
}

/// Statut d'un trajet publié par un conducteur.
enum TripStatus {
  ouvert('ouvert'),
  complet('complet'),
  termine('termine'),
  annule('annule');

  const TripStatus(this.apiValue);
  final String apiValue;

  static TripStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Statut de trajet inconnu : $value'));

  /// A passenger may only request a seat on an open trip.
  bool get isBookable => this == TripStatus.ouvert;
}

/// Statut d'une réservation (demande d'un passager sur un trajet).
enum TripReservationStatus {
  enAttente('en_attente'),
  acceptee('acceptee'),
  refusee('refusee'),
  annulee('annulee');

  const TripReservationStatus(this.apiValue);
  final String apiValue;

  static TripReservationStatus parse(String value) => values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => throw ArgumentError('Statut de réservation inconnu : $value'));

  /// A pending or accepted reservation still counts (it can be cancelled).
  bool get isActive =>
      this == TripReservationStatus.enAttente || this == TripReservationStatus.acceptee;
}
