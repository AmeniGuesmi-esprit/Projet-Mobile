import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../../trips/trip_labels.dart';
import '../../trips/widgets/trip_preference_chips.dart';

/// "12,3 km" with a French decimal comma.
String formatKm(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// First letter of the driver name, for the round avatar.
String initialOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

/// One result of the proximity search (driver, price, route, pastilles).
class TripResultCard extends StatelessWidget {
  const TripResultCard({super.key, required this.trip, required this.onTap});

  final TripDto trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = trip.dateHeureDepart;
    final distance = trip.distanceDepartKm;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.outlineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(initialOf(trip.conducteurNom),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: AppColors.primaryDeep)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(trip.conducteurNom,
                        style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    MoneyText.format(trip.prixParPlaceCentimes),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.primaryDeep),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${trip.departAdresse} → ${trip.arriveeAdresse}',
                style: theme.textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xxs,
                children: [
                  _Info(
                    icon: Icons.schedule,
                    text: '${formatTripDate(when)} · ${formatTripTime(when)}',
                  ),
                  _Info(
                    icon: Icons.event_seat_outlined,
                    text: '${trip.placesDisponibles} place(s)',
                  ),
                  if (distance != null)
                    _Info(
                        icon: Icons.near_me_outlined,
                        text: 'à ${formatKm(distance)}'),
                  if (trip.scoreMatching != null)
                    _Info(
                      icon: Icons.auto_awesome,
                      text: 'Compatibilité ${trip.scoreMatching} %',
                    ),
                  if (trip.ecartHeureMin != null)
                    _Info(
                      icon: Icons.timelapse,
                      text: trip.ecartHeureMin == 0
                          ? 'À l\'heure souhaitée'
                          : '${trip.ecartHeureMin} min d\'écart',
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TripPreferenceChips(trip),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondaryStrong),
        const SizedBox(width: AppSpacing.xxs),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
