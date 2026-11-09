import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/service_badge.dart';

/// Home-screen shortcut (same look as the TeleDoc card): tinted icon,
/// badge, title, subtitle and a chevron.
class ServiceEntryCard extends StatelessWidget {
  /// Card for a service module: badge, colour from [ServiceMeta].
  const ServiceEntryCard({
    super.key,
    required ServiceType this.type,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  }) : label = null,
       color = null,
       badgeIcon = null;

  /// Card for something that is not a service module (e.g. Paiements):
  /// the badge is drawn with [label], [badgeIcon] and [color].
  const ServiceEntryCard.custom({
    super.key,
    required String this.label,
    required IconData this.badgeIcon,
    required Color this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  }) : type = null;

  final ServiceType? type;
  final String? label;
  final IconData? badgeIcon;
  final Color? color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = this.type;
    final color = type != null ? ServiceMeta.of(type).color : this.color!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (type != null)
                        ServiceBadge(type, compact: true)
                      else
                        _Badge(label: label!, icon: badgeIcon!, color: color),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Same pill as a compact [ServiceBadge], for a non-service card.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
