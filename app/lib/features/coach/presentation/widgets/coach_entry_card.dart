import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/service_badge.dart';
import '../coach_theme.dart';
import '../screens/coach_home_screen.dart';

/// "CoachProche" entry point on the home screen (single line in
/// `features/home/home_screen.dart`). Coaches see their sessions; every other
/// role books sessions as a client. The module colour is always paired with
/// the CoachProche badge + label.
class CoachEntryCard extends StatelessWidget {
  const CoachEntryCard({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final role = session.user?.role;
    if (role == null) return const SizedBox.shrink();
    final isCoach = role == UserRole.coach;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => pushCoach<void>(
            context,
            CoachHomeScreen(session: session),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.moduleCoachProche.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.fitness_center_outlined,
                    color: AppColors.moduleCoachProche,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ServiceBadge(ServiceType.coachProche,
                          compact: true),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        isCoach
                            ? 'Vos séances de coaching'
                            : 'Séances de sport près de vous',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        isCoach
                            ? 'Publiez vos séances, validez les présences'
                            : 'Réservez, suivez vos pas et votre cœur',
                        style: theme.textTheme.bodySmall,
                      ),
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
