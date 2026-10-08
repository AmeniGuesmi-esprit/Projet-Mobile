import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Pill showing a transaction status with the canonical ProxiLife tint
/// recipe (10 % tint background, colored label, 35 % border).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final TransactionStatus status;

  static const Map<TransactionStatus, String> _labels = {
    TransactionStatus.enAttente: 'En attente',
    TransactionStatus.paye: 'Payé',
    TransactionStatus.echoue: 'Échoué',
    TransactionStatus.rembourse: 'Remboursé',
  };

  // WARNING uses dark text on light tint (contrast rule from the design skill).
  static const Map<TransactionStatus, Color> _colors = {
    TransactionStatus.enAttente: AppColors.info,
    TransactionStatus.paye: AppColors.success,
    TransactionStatus.echoue: AppColors.error,
    TransactionStatus.rembourse: AppColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status]!;
    final darkText = status == TransactionStatus.rembourse;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _labels[status]!,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: darkText ? AppColors.text : color,
        ),
      ),
    );
  }
}
