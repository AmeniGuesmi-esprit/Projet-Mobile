import '../enums.dart';
import 'service_now_advanced_dto.dart';
import 'service_now_enums.dart';

/// Validation rules and state machines of the ServiceNow module. The app
/// (instant feedback) and the server (authoritative) both use this class.
class ServiceNowRules {
  const ServiceNowRules._();

  static const int minDescriptionLength = 10;
  static const int maxDescriptionLength = 1000;
  static const int maxAddressLength = 300;
  static const int minReportLength = 5;
  static const int maxReportLength = 2000;

  /// Maximum price of an intervention, in centimes (5 000 DT).
  static const int maxPriceCentimes = 500000;

  /// How far ahead a request or an intervention can be scheduled.
  static const int maxDaysAhead = 365;

  static const Map<DemandeServiceStatus, Set<DemandeServiceStatus>>
      _demandeTransitions = {
    DemandeServiceStatus.enAttente: {
      DemandeServiceStatus.acceptee,
      DemandeServiceStatus.annulee,
    },
    DemandeServiceStatus.acceptee: {
      // The prestataire withdrew: the request goes back to the pool.
      DemandeServiceStatus.enAttente,
      DemandeServiceStatus.enCours,
      DemandeServiceStatus.annulee,
    },
    DemandeServiceStatus.enCours: {
      DemandeServiceStatus.terminee,
      DemandeServiceStatus.annulee,
    },
    DemandeServiceStatus.terminee: {},
    DemandeServiceStatus.annulee: {},
  };

  static const Map<InterventionStatus, Set<InterventionStatus>>
      _interventionTransitions = {
    InterventionStatus.planifiee: {
      InterventionStatus.enCours,
      InterventionStatus.annulee,
    },
    InterventionStatus.enCours: {
      InterventionStatus.terminee,
      InterventionStatus.annulee,
    },
    InterventionStatus.terminee: {},
    InterventionStatus.annulee: {},
  };

  static bool canMoveDemande(
    DemandeServiceStatus from,
    DemandeServiceStatus to,
  ) =>
      _demandeTransitions[from]!.contains(to);

  static bool canMoveIntervention(
    InterventionStatus from,
    InterventionStatus to,
  ) =>
      _interventionTransitions[from]!.contains(to);

  /// A request can only be edited before a prestataire takes it.
  static bool clientCanEdit(DemandeServiceStatus status) =>
      status == DemandeServiceStatus.enAttente;

  /// A client can cancel until the work has started. Only an admin can stop
  /// an intervention in progress.
  static bool clientCanCancel(DemandeServiceStatus status) =>
      status == DemandeServiceStatus.enAttente ||
      status == DemandeServiceStatus.acceptee;

  /// Payable once finished, unless a payment already exists. A failed
  /// payment or a cancelled cash payment can be attempted again.
  static bool canPay(InterventionStatus status, TransactionStatus? payment) =>
      status == InterventionStatus.terminee &&
      (payment == null || payment == TransactionStatus.echoue);

  /// Rated once, after a payment exists (a pending cash payment counts).
  static bool canRate(
    InterventionStatus status,
    TransactionStatus? payment, {
    required bool alreadyRated,
  }) =>
      status == InterventionStatus.terminee &&
      payment != null &&
      payment != TransactionStatus.echoue &&
      !alreadyRated;

  /// Time blocked around an intervention: two of them cannot overlap.
  static const int interventionMinutes = 120;

  static const int maxMessageLength = 1000;

  /// The client and the prestataire can write once he has accepted.
  static bool canChat(DemandeServiceStatus status) =>
      status == DemandeServiceStatus.acceptee ||
      status == DemandeServiceStatus.enCours ||
      status == DemandeServiceStatus.terminee;

  /// Key of a day off, from a local date: "2026-11-12".
  static String dayKey(DateTime local) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  /// Whether a prestataire can take work at [when] (local time). Without
  /// weekly hours he is considered free every day, so that a prestataire who
  /// has not filled in his calendar is not ruled out.
  static bool isAvailable(
    DateTime when, {
    required List<DisponibiliteSlotDto> slots,
    required Set<String> joursOff,
    required List<DateTime> busy,
  }) {
    if (joursOff.contains(dayKey(when))) return false;
    final overlaps = busy.any(
      (other) => other.difference(when).inMinutes.abs() < interventionMinutes,
    );
    if (overlaps) return false;
    if (slots.isEmpty) return true;
    final minutes = when.hour * 60 + when.minute;
    return slots.any((slot) =>
        slot.jour == when.weekday &&
        slot.debutMinutes <= minutes &&
        minutes < slot.finMinutes);
  }

  /// The higher, the better the match (between 0 and 1). Half the score is
  /// distance, then specialty, then rating. Unknown values count as average
  /// so that a missing location or a new prestataire is not ruled out.
  static double matchScore({
    required double? distanceKm,
    required bool specialty,
    required double? rating,
  }) {
    final proximity = distanceKm == null ? 0.3 : 1 / (1 + distanceKm / 5);
    final quality = rating == null ? 0.6 : rating / 5;
    return 0.5 * proximity + 0.3 * (specialty ? 1 : 0) + 0.2 * quality;
  }

  /// Number of past prices needed before trusting them over [defaultPriceRange].
  static const int minPricesForEstimate = 3;

  /// Usual price range of a service, in centimes, used without enough history.
  static (int, int) defaultPriceRange(ServiceNowType type) => switch (type) {
        ServiceNowType.plomberie => (3000, 12000),
        ServiceNowType.electricite => (4000, 15000),
        ServiceNowType.menage => (2500, 8000),
        ServiceNowType.jardinage => (3000, 10000),
        ServiceNowType.bricolage => (2500, 9000),
        ServiceNowType.climatisation => (6000, 25000),
        ServiceNowType.peinture => (8000, 40000),
        ServiceNowType.autre => (3000, 15000),
      };

  /// Middle half of the past prices, or the default range without enough of
  /// them. Returns (minimum, maximum, number of prices used).
  static (int, int, int) estimatePrice(
    ServiceNowType type,
    List<int> pastPrices,
  ) {
    if (pastPrices.length < minPricesForEstimate) {
      final (low, high) = defaultPriceRange(type);
      return (low, high, 0);
    }
    final sorted = [...pastPrices]..sort();
    final low = sorted[(sorted.length - 1) ~/ 4];
    final high = sorted[((sorted.length - 1) * 3) ~/ 4];
    return (low, high, sorted.length);
  }

  /// Each method returns a French error message, or `null` when valid.
  static String? messageError(String value) {
    final length = value.trim().length;
    if (length == 0) return 'Message vide';
    if (length > maxMessageLength) return 'Message trop long';
    return null;
  }

  static String? slotError(DisponibiliteSlotDto slot) {
    if (slot.jour < 1 || slot.jour > 7) return 'Jour invalide';
    if (slot.debutMinutes < 0 ||
        slot.finMinutes > 24 * 60 ||
        slot.debutMinutes >= slot.finMinutes) {
      return 'L\'heure de fin doit être après l\'heure de début';
    }
    return null;
  }

  static String? dayOffError(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
              DateTime.tryParse(value) != null
          ? null
          : 'Date invalide';

  static String? ratingError(int value) =>
      value < 1 || value > 5 ? 'La note doit être comprise entre 1 et 5' : null;

  static String? commentError(String value) => value.trim().length > 500
      ? 'Commentaire trop long (500 caractères maximum)'
      : null;

  static String? descriptionError(String value) {
    final length = value.trim().length;
    if (length < minDescriptionLength) {
      return 'Décrivez le besoin en $minDescriptionLength caractères minimum';
    }
    if (length > maxDescriptionLength) {
      return 'Description trop longue ($maxDescriptionLength caractères maximum)';
    }
    return null;
  }

  static String? addressError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Adresse obligatoire';
    if (trimmed.length > maxAddressLength) return 'Adresse trop longue';
    return null;
  }

  static String? scheduleError(DateTime when, {required DateTime now}) {
    if (when.isBefore(now)) return 'Choisissez une date à venir';
    if (when.isAfter(now.add(const Duration(days: maxDaysAhead)))) {
      return 'Choisissez une date dans les $maxDaysAhead prochains jours';
    }
    return null;
  }

  static String? priceError(int centimes) {
    if (centimes <= 0 || centimes > maxPriceCentimes) {
      return 'Le prix doit être compris entre 0,01 et '
          '${maxPriceCentimes ~/ 100} DT';
    }
    return null;
  }

  static String? reportError(String value) {
    final length = value.trim().length;
    if (length < minReportLength) {
      return 'Résumez le travail réalisé en $minReportLength caractères minimum';
    }
    if (length > maxReportLength) {
      return 'Rapport trop long ($maxReportLength caractères maximum)';
    }
    return null;
  }
}
