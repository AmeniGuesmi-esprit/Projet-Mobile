import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Small coloured label of a reservation status.
class ReservationStatusBadge extends StatelessWidget {
  const ReservationStatusBadge(this.status, {super.key});

  final TripReservationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TripReservationStatus.enAttente => ('En attente', AppColors.warning),
      TripReservationStatus.acceptee => ('Acceptée', AppColors.success),
      TripReservationStatus.refusee => ('Refusée', AppColors.error),
      TripReservationStatus.annulee => ('Annulée', AppColors.textSecondary),
    };
    // Never white or pale text on the yellow: keep the dark text colour.
    final textColor =
        status == TripReservationStatus.enAttente ? AppColors.text : color;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: textColor),
      ),
    );
  }
}
