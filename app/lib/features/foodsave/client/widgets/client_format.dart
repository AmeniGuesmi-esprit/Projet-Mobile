/// French labels for the client FoodSave screens (local time).
///
/// Day / month names are written by hand so no async
/// `initializeDateFormatting` call is needed (widget tests stay simple).
library;

import 'package:proxilife_shared/proxilife_shared.dart';

const List<String> _weekdays = [
  'lun.',
  'mar.',
  'mer.',
  'jeu.',
  'ven.',
  'sam.',
  'dim.',
];

const List<String> _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _two(int v) => v.toString().padLeft(2, '0');

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "18:05" (local time).
String clockFr(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "aujourd'hui", "demain", "hier" or "lun. 14 oct." (local time).
String dayFr(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (_sameDay(l, n)) return "aujourd'hui";
  if (_sameDay(l, n.add(const Duration(days: 1)))) return 'demain';
  if (_sameDay(l, n.subtract(const Duration(days: 1)))) return 'hier';
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

String _capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "Retrait aujourd'hui 18:00–19:00" (or "… lun. 14 oct. 22:00 – mar. 15
/// oct. 01:00" when the window spans two days).
String pickupWindowFr(DateTime start, DateTime end, {DateTime? now}) {
  final s = start.toLocal();
  final e = end.toLocal();
  if (_sameDay(s, e)) {
    return 'Retrait ${dayFr(s, now: now)} ${clockFr(s)}–${clockFr(e)}';
  }
  return 'Retrait ${dayFr(s, now: now)} ${clockFr(s)} – '
      '${dayFr(e, now: now)} ${clockFr(e)}';
}

/// "Aujourd'hui à 21:00".
String dateTimeFr(DateTime d, {DateTime? now}) =>
    '${_capitalized(dayFr(d, now: now))} à ${clockFr(d)}';

/// "Il reste 1 panier" / "Il reste 3 paniers".
String remainingFr(int n) => 'Il reste $n panier${n > 1 ? 's' : ''}';

/// Why [basket] cannot be reserved right now (null when it can). Mirrors the
/// server rules via [FoodSaveRules.canReserve]; the server stays the judge.
String? unavailableReason(BasketDto basket, {DateTime? now, int? viewerId}) {
  final n = (now ?? DateTime.now()).toUtc();
  switch (basket.statut) {
    case BasketStatus.annule:
      return 'Ce panier a été annulé par le commerçant.';
    case BasketStatus.expire:
      return 'Ce panier a expiré : il n\'est plus en vente.';
    case BasketStatus.epuise:
      return 'Panier épuisé : revenez plus tard, des unités peuvent être remises en vente.';
    case BasketStatus.disponible:
      break;
  }
  if (basket.quantite <= 0) {
    return 'Panier épuisé : revenez plus tard, des unités peuvent être remises en vente.';
  }
  if (!n.isBefore(basket.dateExpiration)) {
    return 'Ce panier a expiré : il n\'est plus en vente.';
  }
  if (viewerId != null && viewerId == basket.commercantId) {
    return 'Vous ne pouvez pas réserver votre propre panier.';
  }
  final ok = FoodSaveRules.canReserve(
    status: basket.statut,
    available: basket.quantite,
    quantity: 1,
    pickupEnd: basket.creneauRetraitFin,
    basketExpiry: basket.dateExpiration,
    now: n,
    reservationMinutes: basket.dureeReservationMinutes,
  );
  if (!ok) {
    if (!n.isBefore(basket.creneauRetraitFin)) {
      return 'Le retrait est terminé : ce panier ne peut plus être réservé.';
    }
    return 'Réservations closes depuis ${clockFr(reservationDeadlineOf(basket))} : '
        'ce panier expire à ${clockFr(basket.creneauRetraitFin)} et la durée '
        'de réservation est de ${basket.dureeReservationMinutes} min.';
  }
  return null;
}

/// Last moment [basket] can be reserved (end of pickup - reservation
/// duration).
DateTime reservationDeadlineOf(BasketDto basket) =>
    FoodSaveRules.reservationDeadline(
      pickupEnd: basket.creneauRetraitFin,
      reservationMinutes: basket.dureeReservationMinutes,
    );
