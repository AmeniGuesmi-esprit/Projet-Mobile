import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../service_now_format.dart';

/// Small tinted label of a request status.
class DemandeStatusBadge extends StatelessWidget {
  const DemandeStatusBadge(this.status, {super.key});

  final DemandeServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DemandeServiceStatus.enAttente => AppColors.info,
      DemandeServiceStatus.acceptee => AppColors.primary,
      DemandeServiceStatus.enCours => AppColors.warning,
      DemandeServiceStatus.terminee => AppColors.success,
      DemandeServiceStatus.annulee => AppColors.textSecondaryStrong,
    };
    // Never coloured text on the yellow tint: keep the dark text colour.
    final textColor =
        status == DemandeServiceStatus.enCours ? AppColors.text : color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.label,
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: textColor),
      ),
    );
  }
}

/// One request in a list.
class DemandeCard extends StatelessWidget {
  const DemandeCard({super.key, required this.demande, required this.onTap});

  final DemandeServiceDto demande;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intervention = demande.intervention;
    final date = intervention?.datePrevue ?? demande.dateSouhaitee;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(serviceTypeIcon(demande.type),
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(demande.type.label,
                        style: theme.textTheme.titleMedium),
                  ),
                  DemandeStatusBadge(demande.statut),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                demande.description,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              InfoLine(icon: Icons.place_outlined, text: demande.adresse),
              InfoLine(
                icon: Icons.schedule,
                text: formatServiceDate(date),
              ),
              if (intervention != null)
                InfoLine(
                  icon: Icons.payments_outlined,
                  text: MoneyText.format(intervention.prixCentimes),
                ),
              if (demande.distanceKm != null)
                InfoLine(
                  icon: Icons.near_me_outlined,
                  text: 'À ${formatDistanceKm(demande.distanceKm!)}',
                ),
              if (!demande.disponibleALaDate)
                const InfoLine(
                  icon: Icons.event_busy_outlined,
                  text: 'Hors de vos disponibilités',
                ),
              if (demande.specialiteCorrespond)
                const InfoLine(
                  icon: Icons.verified_outlined,
                  text: 'Votre spécialité',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + text row used on cards and on the detail screen.
class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondaryStrong),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Button picking a date then a time, with its error under it.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value != null && value!.isAfter(now) ? value! : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate:
          now.add(const Duration(days: ServiceNowRules.maxDaysAhead - 1)),
      helpText: label,
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: value == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(value!),
      helpText: label,
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (time == null) return;
    onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _pick(context),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(value == null ? label : formatServiceDate(value!)),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xxs,
              left: AppSpacing.sm,
            ),
            child: Text(
              errorText!,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}
