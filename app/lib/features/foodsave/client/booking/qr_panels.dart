import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../widgets/foodsave_ui.dart';
import '../widgets/client_format.dart';
import 'booking_format.dart';
import 'countdown_ring.dart';

/// Default QR lifetime when the server did not send its creation date.
const Duration _fallbackQrTtl = Duration(minutes: 30);

/// Pickup "ticket": header band (ref), big scannable QR, live
/// countdown and hints. Only the countdown listens to [now], so the QR
/// itself is not rebuilt every second.
class ActiveQrPanel extends StatelessWidget {
  const ActiveQrPanel({
    super.key,
    required this.reservation,
    required this.token,
    required this.now,
    this.emailSentTo,
  });

  final ReservationDto reservation;
  final String token;
  final ValueListenable<DateTime> now;

  /// Client e-mail the server sent a copy of the QR code to.
  final String? emailSentTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiry = reservation.dateExpirationQr;
    final created = reservation.dateCreationQr;
    final total = (expiry != null && created != null)
        ? expiry.difference(created)
        : _fallbackQrTtl;
    final email = emailSentTo;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
        boxShadow: [
          BoxShadow(
            color: AppColors.moduleFoodSaveDeep.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _TicketHeader(reference: reservationRef(reservation.id)),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.moduleFoodSaveSoft,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: QrImageView(
                    key: const ValueKey('reservation-qr'),
                    data: token,
                    size: 240,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    gapless: true,
                    semanticsLabel:
                        'QR code de retrait, ${reservationRef(reservation.id)}',
                  ),
                ),
              ),
            ),
          ),
          if (expiry != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: ValueListenableBuilder<DateTime>(
                valueListenable: now,
                builder: (context, current, _) {
                  final remaining = expiry.difference(current);
                  final level = countdownLevel(remaining);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CountdownRing(
                          remaining: remaining, total: total, size: 64),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expire dans ${formatCountdown(remaining)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: countdownTextColor(level),
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            Text('Valable jusqu\'à ${clockFr(expiry)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondaryStrong)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          const _Perforation(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              children: [
                if (isCashReservation(reservation)) ...[
                  _CashAtPickupNotice(amountCents: reservation.montantCentimes),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (email != null) ...[
                  _EmailNotice(email: email),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const _HintRow(
                  icon: Icons.brightness_high_outlined,
                  text: 'Augmentez la luminosité pour faciliter le scan',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Deep-orange band on top of the ticket (white text passes AA on it).
class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.moduleFoodSaveDeep, Color(0xFF7E3F0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_2_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prêt pour le retrait',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text('À présenter au commerçant',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(reference,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.moduleFoodSaveDeep,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Ticket tear line: two half-circle notches and a dashed rule.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    const notch = 18.0;
    Widget hole() => Container(
          width: notch,
          height: notch,
          decoration: const BoxDecoration(
              color: AppColors.background, shape: BoxShape.circle),
        );
    return SizedBox(
      height: notch,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: notch),
            child: LayoutBuilder(builder: (context, c) {
              const dash = 6.0;
              final count = (c.maxWidth / (dash * 2)).floor();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  count,
                  (_) => Container(
                      width: dash, height: 1.5, color: AppColors.outline),
                ),
              );
            }),
          ),
          Positioned(left: -notch / 2, child: hole()),
          Positioned(right: -notch / 2, child: hole()),
        ],
      ),
    );
  }
}

/// Cash reservations: reminds the client to bring the amount at pickup.
class _CashAtPickupNotice extends StatelessWidget {
  const _CashAtPickupNotice({required this.amountCents});

  final int amountCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.moduleFoodSaveSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: AppColors.moduleFoodSaveDeep.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined,
              size: 20, color: AppColors.moduleFoodSaveDeep),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text('Paiement en espèces au retrait',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.text, fontWeight: FontWeight.w600)),
          ),
          Text(MoneyText.format(amountCents),
              style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.moduleFoodSaveDeep,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmailNotice extends StatelessWidget {
  const _EmailNotice({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read_outlined,
              size: 20, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Une copie a été envoyée à '),
                TextSpan(
                    text: email,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-QR states: expired, picked up, cancelled, awaiting payment.
class QrStatePanel extends StatelessWidget {
  const QrStatePanel({super.key, required this.phase, required this.reservation});

  final QrPhase phase;
  final ReservationDto reservation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final (IconData icon, Color color, String title, String message) =
        switch (phase) {
      QrPhase.pickedUp => (
          Icons.check_rounded,
          AppColors.success,
          'Retrait validé, bon appétit !',
          reservation.retireLe == null
              ? 'Merci d\'avoir sauvé ce panier du gaspillage.'
              : 'Retiré ${dayFr(reservation.retireLe!)} à ${clockFr(reservation.retireLe!)}. '
                  'Merci d\'avoir sauvé ce panier du gaspillage.',
        ),
      QrPhase.expired => (
          Icons.timer_off_outlined,
          AppColors.warning,
          'QR code expiré — le panier a été remis en vente',
          isCashReservation(reservation)
              ? 'Aucun montant n\'est à régler.'
              : 'Aucun remboursement automatique n\'est effectué. '
                  'Contactez le commerçant si vous pensez qu\'il s\'agit d\'une erreur.',
        ),
      QrPhase.cancelled => (
          Icons.block,
          AppColors.error,
          'Réservation annulée',
          isCashReservation(reservation) &&
                  reservation.statutPaiement != TransactionStatus.echoue
              ? 'Aucun montant n\'est à régler.'
              : switch (reservation.statutPaiement) {
                  TransactionStatus.rembourse => 'Vous avez été remboursé.',
                  TransactionStatus.echoue =>
                    'Le paiement a échoué : aucun montant n\'a été débité.',
                  TransactionStatus.paye =>
                    'Le remboursement est en cours de traitement.',
                  TransactionStatus.enAttente =>
                    'Aucun montant n\'a été débité.',
                },
        ),
      QrPhase.awaitingPayment || QrPhase.active => (
          Icons.hourglass_top_rounded,
          AppColors.info,
          'Paiement en cours de confirmation',
          'Le QR code apparaîtra dès que le paiement sera confirmé.',
        ),
    };
    final darkIcon = color == AppColors.warning;
    return _PanelCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1 : 0.6, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: phase == QrPhase.pickedUp
                  ? Curves.easeOutBack
                  : FoodSaveMotion.curve,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: phase == QrPhase.pickedUp
                      ? color
                      : color.withValues(alpha: darkIcon ? 0.22 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 44,
                  color: phase == QrPhase.pickedUp
                      ? Colors.white
                      : (darkIcon ? AppColors.text : color),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryStrong),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: AppColors.moduleFoodSaveDeep),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondaryStrong)),
          ),
        ],
      );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        child: child,
      );
}
