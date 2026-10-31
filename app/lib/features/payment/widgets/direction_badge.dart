import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Compact « Reçu » / « Envoyé » chip shown on transaction rows.
class DirectionBadge extends StatelessWidget {
  const DirectionBadge(this.direction, {super.key});

  /// Null (legacy data) is displayed as « Envoyé » (payer view).
  final TransactionDirection? direction;

  @override
  Widget build(BuildContext context) {
    final isCredit = direction == TransactionDirection.credit;
    final color = isCredit ? AppColors.success : AppColors.textSecondaryStrong;
    final icon = isCredit ? Icons.south_west : Icons.north_east;
    final label = isCredit ? 'Reçu' : 'Envoyé';
    return Semantics(
      label: isCredit ? 'Paiement reçu' : 'Paiement envoyé',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
