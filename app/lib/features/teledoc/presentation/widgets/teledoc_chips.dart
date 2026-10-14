import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Tint pill (same recipe as the core `StatusChip`: 10 % background,
/// 35 % border, coloured label). Colour is never the only signal: every
/// chip has a label, and an icon where the colour could be ambiguous.
class _TintChip extends StatelessWidget {
  const _TintChip({
    required this.label,
    required this.color,
    this.icon,
    this.darkText = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Warning-coloured chips use dark text (contrast rule of the design skill).
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final foreground = darkText ? AppColors.text : color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class TeledocStatusChip extends StatelessWidget {
  const TeledocStatusChip(this.status, {super.key});

  final TeledocRequestStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    TeledocRequestStatus.enAttente => _TintChip(
      label: status.label,
      color: AppColors.info,
      icon: Icons.hourglass_top,
    ),
    TeledocRequestStatus.enCours => _TintChip(
      label: status.label,
      color: AppColors.primary,
      icon: Icons.videocam_outlined,
    ),
    TeledocRequestStatus.terminee => _TintChip(
      label: status.label,
      color: AppColors.success,
      icon: Icons.check_circle_outline,
    ),
    // A cancellation is not an error: neutral colour.
    TeledocRequestStatus.annulee => _TintChip(
      label: status.label,
      color: AppColors.textSecondaryStrong,
      icon: Icons.block,
    ),
  };
}

class TeledocUrgencyChip extends StatelessWidget {
  const TeledocUrgencyChip(this.urgency, {super.key});

  final TeledocUrgency urgency;

  @override
  Widget build(BuildContext context) => switch (urgency) {
    TeledocUrgency.faible => _TintChip(
      label: 'Urgence ${urgency.label.toLowerCase()}',
      color: AppColors.success,
    ),
    TeledocUrgency.moyenne => _TintChip(
      label: 'Urgence ${urgency.label.toLowerCase()}',
      color: AppColors.warning,
      darkText: true,
    ),
    TeledocUrgency.elevee => _TintChip(
      label: 'Urgence ${urgency.label.toLowerCase()}',
      color: AppColors.error,
      icon: Icons.priority_high,
    ),
  };
}
