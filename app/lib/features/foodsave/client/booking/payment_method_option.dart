import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../widgets/foodsave_ui.dart';
import 'booking_format.dart';

/// Selectable "radio card" for one saved payment method.
class PaymentMethodOption extends StatelessWidget {
  const PaymentMethodOption({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
    this.walletBalanceCents,
    this.amountCents = 0,
  });

  final PaymentMethodDto method;
  final bool selected;
  final VoidCallback onTap;

  /// Current wallet balance (only for [PaymentMethodType.portefeuille]).
  final int? walletBalanceCents;
  final int amountCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = paymentMethodTitle(method);
    final balance = walletBalanceCents;
    final insufficient = method.type == PaymentMethodType.portefeuille &&
        balance != null &&
        balance < amountCents;
    final Widget subtitle = switch (method.type) {
      PaymentMethodType.carteBancaire => Text(
          [
            if (method.nomTitulaire != null) method.nomTitulaire!,
            if (method.dateExpiration != null)
              'expire ${method.dateExpiration}',
          ].join(' · '),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondaryStrong),
        ),
      PaymentMethodType.portefeuille => balance == null
          ? Text('Solde interne du compte',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondaryStrong))
          : Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xxs,
              children: [
                Text('Solde :',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondaryStrong)),
                MoneyText(balance,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: insufficient
                            ? AppColors.error
                            : AppColors.textSecondaryStrong)),
                if (insufficient)
                  Text('— insuffisant',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.error)),
              ],
            ),
      PaymentMethodType.especes => Text('Réglé auprès du commerçant',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondaryStrong)),
    };

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '$title${method.parDefaut ? ', par défaut' : ''}',
      child: AnimatedContainer(
        duration: FoodSaveMotion.fast,
        curve: FoodSaveMotion.curve,
        decoration: BoxDecoration(
          color: selected ? AppColors.moduleFoodSaveSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.moduleFoodSave : AppColors.outline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.moduleFoodSave.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(paymentTypeIcon(method.type),
                          color: AppColors.moduleFoodSaveDeep, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(title,
                                  style: theme.textTheme.titleMedium),
                              if (method.parDefaut)
                                Text('Par défaut',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.moduleFoodSaveDeep,
                                        fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          subtitle,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? AppColors.moduleFoodSaveDeep
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
