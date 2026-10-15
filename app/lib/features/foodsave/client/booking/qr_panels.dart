import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../widgets/foodsave_ui.dart';
import '../widgets/client_format.dart';
import 'booking_format.dart';
import 'countdown_ring.dart';

/// Default QR lifetime when the server did not send its creation date.
const Duration _fallbackQrTtl = Duration(minutes: 30);

/// Big scannable QR + live countdown. Only the countdown listens to [now],
/// so the QR itself is not rebuilt every second.
class ActiveQrPanel extends StatelessWidget {
  const ActiveQrPanel({
    super.key,
    required this.reservation,
    required this.token,
    required this.now,
  });

  final ReservationDto reservation;
  final String token;
  final ValueListenable<DateTime> now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiry = reservation.dateExpirationQr;
    final created = reservation.dateCreationQr;
    final total = (expiry != null && created != null)
        ? expiry.difference(created)
        : _fallbackQrTtl;
    return _PanelCard(
      child: Column(
        children: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.outlineSoft),
              ),
              child: QrImageView(
                key: const ValueKey('reservation-qr'),
                data: token,
                size: 256,
                padding: const EdgeInsets.all(AppSpacing.md),
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                gapless: true,
                semanticsLabel:
                    'QR code de retrait, ${reservationRef(reservation.id)}',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (expiry != null)
            ValueListenableBuilder<DateTime>(
              valueListenable: now,
              builder: (context, current, _) {
                final remaining = expiry.difference(current);
                final level = countdownLevel(remaining);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CountdownRing(remaining: remaining, total: total, size: 72),
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
          const SizedBox(height: AppSpacing.md),
          const _HintRow(
            icon: Icons.brightness_high_outlined,
            text: 'Augmentez la luminosité pour faciliter le scan',
          ),
          const SizedBox(height: AppSpacing.xs),
          const _HintRow(
            icon: Icons.storefront_outlined,
            text: 'Présentez ce QR code au commerçant au moment du retrait.',
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
          'Aucun remboursement automatique n\'est effectué. '
              'Contactez le commerçant si vous pensez qu\'il s\'agit d\'une erreur.',
        ),
      QrPhase.cancelled => (
          Icons.block,
          AppColors.error,
          'Réservation annulée',
          switch (reservation.statutPaiement) {
            TransactionStatus.rembourse => 'Vous avez été remboursé.',
            TransactionStatus.echoue =>
              'Le paiement a échoué : aucun montant n\'a été débité.',
            TransactionStatus.paye =>
              'Le remboursement est en cours de traitement.',
            TransactionStatus.enAttente => 'Aucun montant n\'a été débité.',
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
