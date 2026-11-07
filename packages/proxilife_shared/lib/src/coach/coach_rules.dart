/// CoachProche business rules, written once and used by the server
/// (authoritative) and the app (UX feedback only).
library;

class CoachRules {
  const CoachRules._();

  static const int minTitleLength = 3;
  static const int maxTitleLength = 80;
  static const int maxDescriptionLength = 500;
  static const int maxPlaceLength = 120;
  static const int minDurationMinutes = 15;
  static const int maxDurationMinutes = 240;
  static const int minPlaces = 1;
  static const int maxPlaces = 100;

  /// Whole cents. 0 = free session.
  static const int maxPriceCents = 100000;

  /// The coach can scan from this long before the start of the session...
  static const Duration scanOpensBefore = Duration(minutes: 30);

  /// ...until the end of the session.
  /// "Rappel avant la séance" is sent this long before the start.
  static const Duration reminderLead = Duration(minutes: 60);

  /// Average stride used to estimate the distance from the step count.
  static const double stepLengthMeters = 0.75;

  static const int maxSteps = 100000;
  static const int minHeartRate = 30;
  static const int maxHeartRate = 230;

  /// Returns the first problem found (French, user-facing) or `null`.
  static String? validateSession({
    required String titre,
    String? description,
    required String lieu,
    required double latitude,
    required double longitude,
    required DateTime dateHeure,
    required int dureeMinutes,
    required int places,
    required int prixCentimes,
    required DateTime now,
  }) {
    final t = titre.trim();
    if (t.length < minTitleLength || t.length > maxTitleLength) {
      return 'Le titre doit contenir entre $minTitleLength et '
          '$maxTitleLength caractères';
    }
    if ((description?.trim().length ?? 0) > maxDescriptionLength) {
      return 'La description ne peut pas dépasser $maxDescriptionLength '
          'caractères';
    }
    final l = lieu.trim();
    if (l.isEmpty || l.length > maxPlaceLength) {
      return 'Indiquez le lieu de la séance';
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return 'Position GPS invalide : choisissez le lieu via la recherche '
          'd\'adresse';
    }
    if (!dateHeure.isAfter(now)) {
      return 'La séance doit être programmée dans le futur';
    }
    if (dureeMinutes < minDurationMinutes ||
        dureeMinutes > maxDurationMinutes) {
      return 'La durée doit être comprise entre $minDurationMinutes et '
          '$maxDurationMinutes minutes';
    }
    if (places < minPlaces || places > maxPlaces) {
      return 'Le nombre de places doit être compris entre $minPlaces et '
          '$maxPlaces';
    }
    if (prixCentimes < 0 || prixCentimes > maxPriceCents) {
      return 'Le prix doit être compris entre 0 et '
          '${maxPriceCents ~/ 100} DT';
    }
    return null;
  }

  /// Steps / heart rate entered by the client during a session.
  static String? validateMetrics({int? pas, int? frequenceCardiaque}) {
    if (pas == null && frequenceCardiaque == null) {
      return 'Renseignez vos pas ou votre fréquence cardiaque';
    }
    if (pas != null && (pas < 0 || pas > maxSteps)) {
      return 'Le nombre de pas doit être compris entre 0 et $maxSteps';
    }
    if (frequenceCardiaque != null &&
        (frequenceCardiaque < minHeartRate ||
            frequenceCardiaque > maxHeartRate)) {
      return 'La fréquence cardiaque doit être comprise entre '
          '$minHeartRate et $maxHeartRate battements par minute';
    }
    return null;
  }

  /// Distance covered, estimated from the step count (km, 2 decimals).
  static double distanceKmFromSteps(int steps) =>
      (steps * stepLengthMeters / 10).round() / 100;

  /// True while the coach may validate presences for a session.
  static bool isScanWindowOpen(
      DateTime start, int dureeMinutes, DateTime now) {
    final opens = start.subtract(scanOpensBefore);
    final closes = start.add(Duration(minutes: dureeMinutes));
    return !now.isBefore(opens) && now.isBefore(closes);
  }
}
