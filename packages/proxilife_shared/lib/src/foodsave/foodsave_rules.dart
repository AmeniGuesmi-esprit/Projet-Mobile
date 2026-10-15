import 'dart:math' as math;

import 'foodsave_enums.dart';

/// Radius (km) for "nouveau panier" notifications.
const double foodSaveNotificationRadiusKm = 5;

/// Minimum time left in the pickup window to accept a new reservation.
const Duration foodSaveMinPickupLead = Duration(minutes: 5);

/// Canonical FoodSave state machines + validation. The server is
/// authoritative; the app only uses these for UI hints. Never re-implement.
class FoodSaveRules {
  const FoodSaveRules._();

  static const Map<ReservationStatus, Set<ReservationStatus>> _reservation = {
    ReservationStatus.enAttente: {
      ReservationStatus.retire,
      ReservationStatus.expire,
      ReservationStatus.annule,
    },
    ReservationStatus.retire: <ReservationStatus>{},
    ReservationStatus.expire: <ReservationStatus>{},
    ReservationStatus.annule: <ReservationStatus>{},
  };

  static const Map<BasketStatus, Set<BasketStatus>> _basket = {
    BasketStatus.disponible: {
      BasketStatus.epuise,
      BasketStatus.expire,
      BasketStatus.annule,
    },
    // Units released (expiry / cancellation) put a sold-out basket back on sale.
    BasketStatus.epuise: {
      BasketStatus.disponible,
      BasketStatus.expire,
      BasketStatus.annule,
    },
    BasketStatus.expire: <BasketStatus>{},
    BasketStatus.annule: <BasketStatus>{},
  };

  static bool canTransitionReservation(
          ReservationStatus from, ReservationStatus to) =>
      _reservation[from]?.contains(to) ?? false;

  static bool canTransitionBasket(BasketStatus from, BasketStatus to) =>
      _basket[from]?.contains(to) ?? false;

  static bool isReservationActive(ReservationStatus s) =>
      s == ReservationStatus.enAttente;

  static bool isBasketTerminal(BasketStatus s) =>
      s == BasketStatus.expire || s == BasketStatus.annule;

  /// The merchant may still edit price/content/quantity.
  static bool isBasketEditable(BasketStatus s) => !isBasketTerminal(s);

  /// Whether a client can reserve [quantity] units right now.
  static bool canReserve({
    required BasketStatus status,
    required int available,
    required int quantity,
    required DateTime pickupEnd,
    required DateTime basketExpiry,
    required DateTime now,
  }) =>
      status == BasketStatus.disponible &&
      quantity >= 1 &&
      quantity <= available &&
      now.isBefore(basketExpiry) &&
      now.add(foodSaveMinPickupLead).isBefore(pickupEnd);

  /// QR expiry: until the end of the pickup window when reserving before the
  /// window opens; otherwise [ttl] after generation, capped at the window end.
  static DateTime qrExpiry({
    required DateTime now,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    required Duration ttl,
  }) {
    if (now.isBefore(pickupStart)) return pickupEnd;
    final byTtl = now.add(ttl);
    return byTtl.isBefore(pickupEnd) ? byTtl : pickupEnd;
  }

  /// Whole-percent discount, e.g. 1500 → 500 cents = 67.
  static int discountPercent(int priceCents, int initialPriceCents) {
    if (initialPriceCents <= 0 || priceCents >= initialPriceCents) return 0;
    return (((initialPriceCents - priceCents) * 100) / initialPriceCents)
        .round();
  }

  /// Validates basket fields. Returns a French error message or null.
  /// [quantity] is the units currently on sale.
  static String? basketError({
    required String title,
    required String content,
    required int priceCents,
    required int initialPriceCents,
    required int quantity,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    required DateTime expiry,
  }) {
    final t = title.trim();
    if (t.length < 3 || t.length > 80) {
      return 'Le titre doit contenir entre 3 et 80 caractères';
    }
    final c = content.trim();
    if (c.length < 3 || c.length > 500) {
      return 'Le contenu doit contenir entre 3 et 500 caractères';
    }
    if (priceCents <= 0) return 'Le prix réduit doit être supérieur à 0';
    if (initialPriceCents > 100000000) return 'Prix initial trop élevé';
    if (initialPriceCents <= priceCents) {
      return 'Le prix initial doit être supérieur au prix réduit';
    }
    if (quantity < 0) return 'La quantité ne peut pas être négative';
    if (quantity > 999) return 'Quantité trop élevée (999 maximum)';
    if (!pickupEnd.isAfter(pickupStart)) {
      return 'La fin du créneau de retrait doit suivre son début';
    }
    if (expiry.isBefore(pickupEnd)) {
      return 'La date d\'expiration doit être après la fin du créneau de retrait';
    }
    return null;
  }
}

/// Valid WGS84 coordinates (and not the 0,0 "null island" placeholder).
bool isValidLatLng(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    !(latitude == 0 && longitude == 0);

/// Great-circle distance in kilometres (haversine, mean Earth radius).
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0088;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(a)));
}
