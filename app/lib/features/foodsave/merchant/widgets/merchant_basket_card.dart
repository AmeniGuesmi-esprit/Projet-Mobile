import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../data/foodsave_api.dart';
import '../../widgets/foodsave_ui.dart';
import 'merchant_format.dart';

/// Merchant-side basket card: photo (Hero), title, prices, discount, units
/// left, status, active reservations and pickup window.
class MerchantBasketCard extends StatelessWidget {
  const MerchantBasketCard({
    super.key,
    required this.api,
    required this.basket,
    required this.onTap,
  });

  final FoodSaveApi api;
  final BasketDto basket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = basket;
    final active = b.reservationsActives ?? 0;
    final terminal = FoodSaveRules.isBasketTerminal(b.statut);
    final window = formatPickupWindowFr(b.creneauRetraitDebut, b.creneauRetraitFin);
    final semantics = '${b.titre}, ${b.statut.label}, '
        '${MoneyText.format(b.prixCentimes)} au lieu de '
        '${MoneyText.format(b.prixInitialCentimes)}, '
        '${b.quantite} sur ${b.quantiteInitiale} unités restantes, '
        '$active réservation${active > 1 ? 's' : ''} active${active > 1 ? 's' : ''}, '
        'retrait $window';

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Stack(
                    children: [
                      Hero(
                        tag: 'basket-image-${b.id}',
                        child: Opacity(
                          opacity: terminal ? 0.55 : 1,
                          child: BasketImage(
                              api: api,
                              basket: b,
                              height: 96,
                              borderRadius: AppRadius.sm),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.xxs,
                        top: AppSpacing.xxs,
                        child: DiscountBadge(
                          prixCentimes: b.prixCentimes,
                          prixInitialCentimes: b.prixInitialCentimes,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              b.titre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          BasketStatusChip(b.statut),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.xs,
                        children: [
                          MoneyText(
                            b.prixCentimes,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.moduleFoodSaveDeep,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          MoneyText(
                            b.prixInitialCentimes,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondaryStrong,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          _Meta(
                            icon: Icons.inventory_2_outlined,
                            text: '${b.quantite} / ${b.quantiteInitiale}',
                            tooltip: 'Unités restantes / mises en vente',
                          ),
                          _Meta(
                            icon: Icons.qr_code_2,
                            text: '$active réserv.',
                            tooltip: 'Réservations actives',
                            highlight: active > 0,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      _Meta(icon: Icons.schedule, text: window),
                    ],
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

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    this.tooltip,
    this.highlight = false,
  });

  final IconData icon;
  final String text;
  final String? tooltip;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color =
        highlight ? AppColors.moduleFoodSaveDeep : AppColors.textSecondaryStrong;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: highlight ? FontWeight.w700 : null,
                ),
          ),
        ),
      ],
    );
    return tooltip == null ? row : Tooltip(message: tooltip, child: row);
  }
}
