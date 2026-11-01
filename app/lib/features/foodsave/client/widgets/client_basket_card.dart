import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../data/foodsave_api.dart';
import '../../widgets/foodsave_ui.dart';
import 'client_format.dart';

/// Hero tag shared by the list card and the detail header.
String basketHeroTag(int basketId) => 'basket-image-$basketId';

/// "Plus que 2" — low stock hint on the warning tint (dark text, AA).
class LowStockChip extends StatelessWidget {
  const LowStockChip(this.quantity, {super.key});

  final int quantity;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.warning),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_outlined,
                size: 14, color: AppColors.text),
            const SizedBox(width: AppSpacing.xxs),
            Text('Plus que $quantity',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ],
        ),
      );
}

/// Bold reduced price + struck-through initial price.
class BasketPriceBlock extends StatelessWidget {
  const BasketPriceBlock({
    super.key,
    required this.prixCentimes,
    required this.prixInitialCentimes,
    this.large = false,
    this.alignEnd = true,
  });

  final int prixCentimes;
  final int prixInitialCentimes;
  final bool large;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MoneyText(
          prixCentimes,
          style: (large ? theme.headlineMedium : theme.titleMedium)?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.moduleFoodSaveDeep),
        ),
        if (prixInitialCentimes > prixCentimes)
          MoneyText(
            prixInitialCentimes,
            style: (large ? theme.bodyLarge : theme.bodySmall)?.copyWith(
              color: AppColors.textSecondaryStrong,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.textSecondaryStrong,
            ),
          ),
      ],
    );
  }
}

/// Client-side basket card (discovery list, map preview).
class ClientBasketCard extends StatelessWidget {
  const ClientBasketCard({
    super.key,
    required this.api,
    required this.basket,
    required this.onTap,
    this.imageHeight = 150,
    this.now,
  });

  final FoodSaveApi api;
  final BasketDto basket;
  final VoidCallback onTap;
  final double imageHeight;

  /// Clock override (tests); defaults to the device clock.
  final DateTime? now;

  String _semanticLabel() {
    final pct =
        FoodSaveRules.discountPercent(basket.prixCentimes, basket.prixInitialCentimes);
    return [
      basket.titre,
      if (basket.commerce != null) basket.commerce!.nom,
      '${MoneyText.format(basket.prixCentimes)} au lieu de '
          '${MoneyText.format(basket.prixInitialCentimes)}',
      if (pct > 0) 'réduction de $pct pour cent',
      if (basket.distanceKm != null)
        'à ${DistancePill.format(basket.distanceKm!)}',
      pickupWindowFr(basket.creneauRetraitDebut, basket.creneauRetraitFin,
          now: now),
      if (basket.quantite <= 2) 'plus que ${basket.quantite}',
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final store = basket.commerce;
    return Semantics(
      button: true,
      label: _semanticLabel(),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.outlineSoft),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Hero(
                    tag: basketHeroTag(basket.id),
                    child: BasketImage(
                      api: api,
                      basket: basket,
                      height: imageHeight,
                      borderRadius: 0,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: DiscountBadge(
                      prixCentimes: basket.prixCentimes,
                      prixInitialCentimes: basket.prixInitialCentimes,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(basket.titre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.titleMedium),
                              if (store != null) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Row(
                                  children: [
                                    const Icon(Icons.storefront_outlined,
                                        size: 16,
                                        color: AppColors.textSecondaryStrong),
                                    const SizedBox(width: AppSpacing.xxs),
                                    Flexible(
                                      child: Text(store.nom,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.bodyMedium?.copyWith(
                                              color: AppColors
                                                  .textSecondaryStrong)),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        BasketPriceBlock(
                          prixCentimes: basket.prixCentimes,
                          prixInitialCentimes: basket.prixInitialCentimes,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DistancePill(basket.distanceKm),
                        if (basket.quantite > 0 && basket.quantite <= 2)
                          LowStockChip(basket.quantite),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule,
                                size: 16, color: AppColors.moduleFoodSaveDeep),
                            const SizedBox(width: AppSpacing.xxs),
                            Flexible(
                              child: Text(
                                pickupWindowFr(basket.creneauRetraitDebut,
                                    basket.creneauRetraitFin,
                                    now: now),
                                style: theme.bodySmall?.copyWith(
                                    color: AppColors.textSecondaryStrong,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
