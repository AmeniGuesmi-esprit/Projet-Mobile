import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../data/foodsave_api.dart';
import '../../widgets/foodsave_ui.dart';
import '../widgets/client_format.dart';
import 'booking_format.dart';

/// One row of "Mes réservations". Active rows show a countdown driven by
/// the screen's shared [now] notifier (no timer per row).
class ReservationCard extends StatelessWidget {
  const ReservationCard({
    super.key,
    required this.api,
    required this.reservation,
    required this.now,
    required this.onTap,
  });

  final FoodSaveApi api;
  final ReservationDto reservation;
  final ValueListenable<DateTime> now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reservation;
    final basket = r.panier;
    final store = basket?.commerce;
    final title = basket?.titre ?? 'Panier anti-gaspillage';
    final expiry = r.dateExpirationQr;
    final showCountdown = isActiveReservation(r) &&
        expiry != null &&
        r.statutPaiement == TransactionStatus.paye;
    return Semantics(
      button: true,
      label: '$title${store == null ? '' : ', ${store.nom}'}, '
          '${r.statut.label}, ${basketsCount(r.quantiteReservee)}, '
          '${MoneyText.format(r.montantCentimes)}',
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.outlineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: basket == null
                      ? Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.moduleFoodSaveSoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Icon(Icons.shopping_basket_outlined,
                              color: AppColors.moduleFoodSave),
                        )
                      : BasketImage(
                          api: api,
                          basket: basket,
                          height: 72,
                          borderRadius: AppRadius.sm),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (store != null)
                          Text(store.nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondaryStrong)),
                        if (basket != null)
                          Text(
                            pickupWindowFr(basket.creneauRetraitDebut,
                                basket.creneauRetraitFin),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondaryStrong),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ReservationStatusChip(r.statut),
                            ReservationPaymentChip(r),
                            if (showCountdown)
                              _CountdownChip(expiry: expiry, now: now),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${basketsCount(r.quantiteReservee)} · ${reservationRef(r.id)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondaryStrong),
                              ),
                            ),
                            MoneyText(r.montantCentimes,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.expiry, required this.now});

  final DateTime expiry;
  final ValueListenable<DateTime> now;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime>(
        valueListenable: now,
        builder: (context, current, _) {
          final remaining = expiry.difference(current);
          final expired = remaining <= Duration.zero;
          final level = countdownLevel(remaining);
          final color = expired ? AppColors.warning : countdownColor(level);
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                    size: 14, color: AppColors.text),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  expired
                      ? 'QR expiré'
                      : 'Expire dans ${formatCountdown(remaining)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
