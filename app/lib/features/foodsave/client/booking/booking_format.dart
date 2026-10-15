/// Small helpers shared by the FoodSave booking screens (reserve flow, QR
/// screen, "Mes réservations"). French labels, local time.
library;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';

/// Injectable clock (tests pass a fake one). Returns any time zone; callers
/// compare with UTC DTO dates through [DateTime.isBefore] / [difference].
typedef BookingClock = DateTime Function();

DateTime systemClock() => DateTime.now();

String _two(int v) => v.toString().padLeft(2, '0');

/// "12:34" (under one hour) or "1:05:09". Negative durations show "00:00".
String formatCountdown(Duration d) {
  if (d.isNegative) return '00:00';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// Spoken form for screen readers: "12 minutes et 34 secondes".
String spokenCountdown(Duration d) {
  if (d.isNegative || d == Duration.zero) return 'expiré';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final parts = <String>[
    if (h > 0) '$h heure${h > 1 ? 's' : ''}',
    if (m > 0) '$m minute${m > 1 ? 's' : ''}',
    if (h == 0 && s > 0) '$s seconde${s > 1 ? 's' : ''}',
  ];
  return parts.join(' et ');
}

/// Urgency of a QR countdown: drives the ring / text colours.
enum CountdownLevel { normal, warning, critical }

CountdownLevel countdownLevel(Duration remaining) {
  if (remaining < const Duration(minutes: 2)) return CountdownLevel.critical;
  if (remaining < const Duration(minutes: 10)) return CountdownLevel.warning;
  return CountdownLevel.normal;
}

/// Ring / fill colour (never used behind white text).
Color countdownColor(CountdownLevel level) => switch (level) {
      CountdownLevel.normal => AppColors.moduleFoodSave,
      CountdownLevel.warning => AppColors.warning,
      CountdownLevel.critical => AppColors.error,
    };

/// Text colour on a white surface (AA contrast for each level).
Color countdownTextColor(CountdownLevel level) => switch (level) {
      CountdownLevel.normal => AppColors.moduleFoodSaveDeep,
      CountdownLevel.warning => AppColors.text,
      CountdownLevel.critical => AppColors.error,
    };

/// Short public reference shown to the client and the merchant.
String reservationRef(int id) => 'Réf. FS-$id';

String paymentTypeLabel(PaymentMethodType type) => switch (type) {
      PaymentMethodType.carteBancaire => 'Carte bancaire',
      PaymentMethodType.portefeuille => 'Portefeuille',
      PaymentMethodType.especes => 'Espèces',
    };

IconData paymentTypeIcon(PaymentMethodType type) => switch (type) {
      PaymentMethodType.carteBancaire => Icons.credit_card,
      PaymentMethodType.portefeuille => Icons.account_balance_wallet_outlined,
      PaymentMethodType.especes => Icons.payments_outlined,
    };

/// "Carte •••• 4242" / "Portefeuille" / "Espèces".
String paymentMethodTitle(PaymentMethodDto m) => switch (m.type) {
      PaymentMethodType.carteBancaire =>
        'Carte •••• ${m.quatreDerniersChiffres ?? '----'}',
      PaymentMethodType.portefeuille => 'Portefeuille ProxiLife',
      PaymentMethodType.especes => 'Espèces',
    };

/// "2 paniers" / "1 panier".
String basketsCount(int n) => '$n panier${n > 1 ? 's' : ''}';

/// Whether [r] should be listed under "En cours".
bool isActiveReservation(ReservationDto r) =>
    r.statut == ReservationStatus.enAttente;

/// Visual phase of a reservation on the QR screen at [now].
enum QrPhase { active, awaitingPayment, expired, pickedUp, cancelled }

QrPhase qrPhaseOf(ReservationDto r, DateTime now) {
  switch (r.statut) {
    case ReservationStatus.retire:
      return QrPhase.pickedUp;
    case ReservationStatus.annule:
      return QrPhase.cancelled;
    case ReservationStatus.expire:
      return QrPhase.expired;
    case ReservationStatus.enAttente:
      final expiry = r.dateExpirationQr;
      if (expiry != null && !now.isBefore(expiry)) return QrPhase.expired;
      if (r.qrToken == null || r.statutPaiement != TransactionStatus.paye) {
        return QrPhase.awaitingPayment;
      }
      return QrPhase.active;
  }
}
