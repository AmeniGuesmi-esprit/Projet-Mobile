import 'dart:math' as math;

/// Great-circle distance helpers (used to find the nearest on-duty pharmacy).
class GeoDistance {
  const GeoDistance._();

  /// Mean Earth radius (IUGG), in kilometres.
  static const double earthRadiusKm = 6371.0088;

  /// Haversine distance in kilometres between two WGS-84 points.
  ///
  /// `a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)`, `d = 2R · atan2(√a, √(1−a))`.
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusKm * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static bool isValidLatitude(double value) =>
      value.isFinite && value >= -90 && value <= 90;

  static bool isValidLongitude(double value) =>
      value.isFinite && value >= -180 && value <= 180;

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
