import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/service_badge.dart';
import '../screens/teledoc_home_screen.dart';

/// "TeleDoc Express" entry point on the home screen (single line in
/// `features/home/home_screen.dart`). Only shown to patients and doctors.
/// The module colour is always paired with the TeleDoc badge + label.
class TeledocEntryCard extends StatelessWidget {
  const TeledocEntryCard({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final role = session.user?.role;
    if (role != UserRole.client && role != UserRole.medecin) {
      return const SizedBox.shrink();
    }
    final isDoctor = role == UserRole.medecin;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TeledocHomeScreen(session: session),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.moduleTeleDoc.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: AppColors.moduleTeleDoc,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ServiceBadge(ServiceType.teleDoc, compact: true),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        isDoctor
                            ? 'Votre file de patients'
                            : 'Consulter un médecin à distance',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        isDoctor
                            ? 'Prendre en charge la prochaine demande'
                            : 'Audio ou vidéo, sans vous déplacer',
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
