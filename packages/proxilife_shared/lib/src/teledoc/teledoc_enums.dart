/// TeleDoc Express enumerations, same pattern as `../enums.dart`:
/// [apiValue] is the snake_case value stored in SQLite and sent over HTTP,
/// [parse] throws [ArgumentError] on unknown values.
library;

/// Lifecycle of a consultation request (see [TeledocRequestRules]).
enum TeledocRequestStatus {
  enAttente('en_attente', 'En attente'),
  enCours('en_cours', 'En consultation'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const TeledocRequestStatus(this.apiValue, this.label);
  final String apiValue;

  /// French label for the UI.
  final String label;

  static TeledocRequestStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de demande inconnu : $value'));
}

/// Urgency declared by the patient. [priority] orders the queue: the higher,
/// the earlier the request is handled.
enum TeledocUrgency {
  faible('faible', 'Faible', 0),
  moyenne('moyenne', 'Moyenne', 1),
  elevee('elevee', 'Élevée', 2);

  const TeledocUrgency(this.apiValue, this.label, this.priority);
  final String apiValue;
  final String label;
  final int priority;

  static TeledocUrgency parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Urgence inconnue : $value'));
}

enum TeledocConsultationType {
  audio('audio', 'Audio'),
  video('video', 'Vidéo');

  const TeledocConsultationType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static TeledocConsultationType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Type de consultation inconnu : $value'));
}

/// Who performs a status transition. Patients are users with the `client`
/// role, doctors the `medecin` role.
enum TeledocActor { patient, medecin }
