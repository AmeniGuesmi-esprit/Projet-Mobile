import 'dart:math' as math;

/// Validation rules and geometry helpers of the carpooling module. Both the
/// app (instant feedback) and the server (authoritative) use this class —
/// never re-implement these rules.
class TripRules {
  const TripRules._();

  /// Maximum passenger seats on one vehicle / one trip.
  static const int maxSeats = 8;

  /// Maximum price per seat, in centimes (1 000 DT).
  static const int maxPriceCentimes = 100000;

  static const int maxTextLength = 120;

  /// Minimum distance between departure and arrival, in km.
  static const double minTripDistanceKm = 0.1;

  static bool isValidLatitude(double value) => value >= -90 && value <= 90;
  static bool isValidLongitude(double value) => value >= -180 && value <= 180;

  /// Returns a French error message, or `null` when the place is valid.
  static String? placeError(
    String label,
    String address,
    double? latitude,
    double? longitude,
  ) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return '$label : adresse obligatoire';
    if (trimmed.length > maxTextLength) return '$label : adresse trop longue';
    if (latitude == null ||
        longitude == null ||
        !isValidLatitude(latitude) ||
        !isValidLongitude(longitude)) {
      return '$label : position invalide';
    }
    return null;
  }

  static String? seatsError(int seats) {
    if (seats < 1 || seats > maxSeats) {
      return 'Le nombre de places doit être entre 1 et $maxSeats';
    }
    return null;
  }

  static String? priceError(int centimes) {
    if (centimes < 0 || centimes > maxPriceCentimes) {
      return 'Le prix par place doit être entre 0 et ${maxPriceCentimes ~/ 100} DT';
    }
    return null;
  }

  /// Great-circle distance in kilometres (Haversine formula).
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static double _rad(double degrees) => degrees * math.pi / 180;
}
