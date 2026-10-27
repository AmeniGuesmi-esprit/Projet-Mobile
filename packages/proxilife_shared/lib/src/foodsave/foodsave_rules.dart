import 'dart:math' as math;

import 'foodsave_enums.dart';

/// Radius (km) for "nouveau panier" notifications.
const double foodSaveNotificationRadiusKm = 5;

/// Minimum time left in the pickup window to accept a new reservation.
const Duration foodSaveMinPickupLead = Duration(minutes: 5);

/// A basket stays on sale at least this long after its start.
const Duration foodSaveMinOpenDuration = Duration(hours: 1);

/// Reservation (QR) lifetime chosen by the merchant, in minutes.
const int foodSaveDefaultReservationMinutes = 30;
const int foodSaveMinReservationMinutes = 5;
const int foodSaveMaxReservationMinutes = 240;

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

  /// Time a reservation needs before the end of the pickup window: the
  /// basket's reservation duration, and never less than
  /// [foodSaveMinPickupLead].
  static Duration reservationLead(int reservationMinutes) {
    final d = Duration(minutes: reservationMinutes);
    return d > foodSaveMinPickupLead ? d : foodSaveMinPickupLead;
  }

  /// Last moment a basket can be reserved: e.g. pickup until 23:00 with a
  /// 15-minute reservation duration → reservations close at 22:45.
  static DateTime reservationDeadline({
    required DateTime pickupEnd,
    required int reservationMinutes,
  }) =>
      pickupEnd.subtract(reservationLead(reservationMinutes));

  /// Whether a client can reserve [quantity] units right now.
  static bool canReserve({
    required BasketStatus status,
    required int available,
    required int quantity,
    required DateTime pickupEnd,
    required DateTime basketExpiry,
    required DateTime now,
    int reservationMinutes = 0,
  }) =>
      status == BasketStatus.disponible &&
      quantity >= 1 &&
      quantity <= available &&
      now.isBefore(basketExpiry) &&
      now.isBefore(reservationDeadline(
          pickupEnd: pickupEnd, reservationMinutes: reservationMinutes));

  /// QR expiry: [ttl] (the basket's reservation duration) after the
  /// reservation — counted from the window opening when reserving before
  /// it — and never after the end of the pickup window.
  static DateTime qrExpiry({
    required DateTime now,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    required Duration ttl,
  }) {
    final from = now.isBefore(pickupStart) ? pickupStart : now;
    final byTtl = from.add(ttl);
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
    int reservationMinutes = foodSaveDefaultReservationMinutes,
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
    if (expiry.isBefore(pickupStart.add(foodSaveMinOpenDuration))) {
      return 'La date d\'expiration doit être au moins 1 h après le début';
    }
    if (reservationMinutes < foodSaveMinReservationMinutes ||
        reservationMinutes > foodSaveMaxReservationMinutes) {
      return 'La durée de réservation doit être comprise entre '
          '$foodSaveMinReservationMinutes et '
          '$foodSaveMaxReservationMinutes minutes';
    }
    final openMinutes = pickupEnd.difference(pickupStart).inMinutes;
    if (reservationMinutes > openMinutes) {
      return 'La durée de réservation ne peut pas dépasser la durée de mise '
          'en vente ($openMinutes min entre le début et l\'expiration)';
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
