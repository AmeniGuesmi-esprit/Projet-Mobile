/// CoachProche (coaching sportif) enumerations shared by the app and the
/// server. Same convention as `enums.dart`: [apiValue] is the snake_case
/// string stored in the database and exchanged over HTTP.
library;

/// Sport practised during a session.
enum CoachSessionType {
  yoga('yoga'),
  running('running'),
  musculation('musculation'),
  fitness('fitness'),
  danse('danse'),
  boxe('boxe');

  const CoachSessionType(this.apiValue);
  final String apiValue;

  static CoachSessionType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Type de séance inconnu : $value'));

  String get label => switch (this) {
        CoachSessionType.yoga => 'Yoga',
        CoachSessionType.running => 'Running',
        CoachSessionType.musculation => 'Musculation',
        CoachSessionType.fitness => 'Fitness',
        CoachSessionType.danse => 'Danse',
        CoachSessionType.boxe => 'Boxe',
      };
}

/// Difficulty level of a session.
enum CoachLevel {
  debutant('debutant'),
  intermediaire('intermediaire'),
  avance('avance');

  const CoachLevel(this.apiValue);
  final String apiValue;

  static CoachLevel parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Niveau inconnu : $value'));

  String get label => switch (this) {
        CoachLevel.debutant => 'Débutant',
        CoachLevel.intermediaire => 'Intermédiaire',
        CoachLevel.avance => 'Avancé',
      };
}

/// Lifecycle of a session. "Terminée" is not stored: a planned session whose
/// end date is past is simply over.
enum CoachSessionStatus {
  planifiee('planifiee'),
  annulee('annulee');

  const CoachSessionStatus(this.apiValue);
  final String apiValue;

  static CoachSessionStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de séance inconnu : $value'));

  String get label => switch (this) {
        CoachSessionStatus.planifiee => 'Planifiée',
        CoachSessionStatus.annulee => 'Annulée',
      };
}

/// Lifecycle of a booking (réservation).
///  - enAttente : booked, payment still to be collected (cash at the session)
///  - confirmee : booked and paid (or free)
///  - present   : the coach scanned the QR code
///  - annulee   : cancelled by the client or the coach (the seat is freed)
enum CoachBookingStatus {
  enAttente('en_attente'),
  confirmee('confirmee'),
  annulee('annulee'),
  present('present');

  const CoachBookingStatus(this.apiValue);
  final String apiValue;

  static CoachBookingStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de réservation inconnu : $value'));

  String get label => switch (this) {
        CoachBookingStatus.enAttente => 'En attente',
        CoachBookingStatus.confirmee => 'Confirmée',
        CoachBookingStatus.annulee => 'Annulée',
        CoachBookingStatus.present => 'Présent',
      };

  /// The booking still holds a seat and can be cancelled.
  bool get isActive =>
      this == CoachBookingStatus.enAttente ||
      this == CoachBookingStatus.confirmee;
}

/// Kind of in-app notification.
enum CoachNotificationType {
  reservationConfirmee('reservation_confirmee'),
  rappelSeance('rappel_seance'),
  seanceAnnulee('seance_annulee'),
  seanceModifiee('seance_modifiee'),
  presenceValidee('presence_validee'),
  nouvelleReservation('nouvelle_reservation'),
  reservationAnnulee('reservation_annulee');

  const CoachNotificationType(this.apiValue);
  final String apiValue;

  static CoachNotificationType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Type de notification inconnu : $value'));
}
