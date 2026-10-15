import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../widgets/foodsave_ui.dart';
import 'merchant_format.dart';

/// One reservation as seen by the merchant: client, quantity, amount,
/// pickup + payment status and, while active, a live expiry countdown.
class MerchantReservationTile extends StatelessWidget {
  const MerchantReservationTile({
    super.key,
    required this.reservation,
    this.showBasketTitle = true,
  });

  final ReservationDto reservation;

  /// False inside a basket's own detail page (the title is redundant there).
  final bool showBasketTitle;

  static String initialsOf(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reservation;
    final name = r.clientNom ?? 'Client n° ${r.clientId}';
    final title = r.panier?.titre ?? 'Panier n° ${r.panierId}';
    final what = showBasketTitle
        ? '${r.quantiteReservee} × $title'
        : '${r.quantiteReservee} unité${r.quantiteReservee > 1 ? 's' : ''}';
    final expiry = r.dateExpirationQr;
    final active = FoodSaveRules.isReservationActive(r.statut);

    return Semantics(
      container: true,
      label: '$name, $what, ${MoneyText.format(r.montantCentimes)}, '
          '${r.statut.label}, réservé ${formatDateTimeFr(r.date)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.moduleFoodSaveSoft,
                child: Text(
                  initialsOf(r.clientNom),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.moduleFoodSaveDeep),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      MoneyText(
                        r.montantCentimes,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$what · ${formatDateTimeFr(r.date)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondaryStrong),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ReservationStatusChip(r.statut),
                      StatusChip(r.statutPaiement),
                      if (active && expiry != null)
                        ExpiryCountdown(expiresAt: expiry),
                      if (r.statut == ReservationStatus.retire &&
                          r.retireLe != null)
                        Text('Retiré ${formatDateTimeFr(r.retireLe!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondaryStrong)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Expire dans 12 min" — ticks on its own (only this leaf rebuilds) and
/// switches to the warning tint (dark text) in the last 10 minutes.
class ExpiryCountdown extends StatefulWidget {
  const ExpiryCountdown({super.key, required this.expiresAt, this.now});

  final DateTime expiresAt;

  /// Injectable clock for tests.
  final DateTime Function()? now;

  @override
  State<ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<ExpiryCountdown> {
  Timer? _timer;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ExpiryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final left = widget.expiresAt.difference(_now());
    if (left.isNegative) return;
    // Second precision only matters in the last minutes.
    final tick = left.inMinutes < 2
        ? const Duration(seconds: 1)
        : const Duration(seconds: 20);
    _timer = Timer(tick, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(_now());
    final expired = left.isNegative || left == Duration.zero;
    final soon = left < const Duration(minutes: 10);
    final color = expired
        ? AppColors.textSecondaryStrong
        : soon
            ? AppColors.warning
            : AppColors.info;
    final fg = soon && !expired ? AppColors.text : color;
    final label =
        expired ? 'Délai dépassé' : 'Expire dans ${formatRemainingFr(left)}';
    return AnimatedContainer(
      duration: FoodSaveMotion.fast,
      curve: FoodSaveMotion.curve,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: soon && !expired ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
