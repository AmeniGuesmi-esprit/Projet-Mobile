import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../trip_labels.dart';

/// The "pastilles" of a trip: ambiance, smoking, pets, women only.
class TripPreferenceChips extends StatelessWidget {
  const TripPreferenceChips(this.trip, {super.key});

  final TripDto trip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (trip.ambiance != Ambiance.indifferent)
          _Pill(
            icon: trip.ambiance == Ambiance.silence
                ? Icons.volume_off_outlined
                : Icons.forum_outlined,
            label: trip.ambiance.label,
          ),
        _Pill(
          icon: trip.fumeurAccepte
              ? Icons.smoking_rooms_outlined
              : Icons.smoke_free_outlined,
          label: trip.fumeurAccepte ? 'Fumeur accepté' : 'Non-fumeur',
        ),
        if (trip.animauxAcceptes)
          const _Pill(icon: Icons.pets_outlined, label: 'Animaux'),
        if (trip.reserveAuxFemmes)
          const _Pill(icon: Icons.female, label: 'Femmes'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primaryDeep),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.primaryDeep),
          ),
        ],
      ),
    );
  }
}
