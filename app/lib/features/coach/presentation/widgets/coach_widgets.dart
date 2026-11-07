/// Small UI kit shared by the CoachProche screens (chips, cards, async view).
library;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../coach_theme.dart';
import 'coach_format.dart';

/// French, user-facing message for any error thrown by [CoachApi].
String coachErrorMessage(Object error) => error is ApiException
    ? error.message
    : 'Une erreur inattendue est survenue. Réessayez.';

/// Floating snackbar (flutter-ux-patterns), optionally with an action.
void showCoachSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

/// Title of a saved payment method ("Carte •••• 4242", "Espèces"...).
String coachMethodTitle(PaymentMethodDto m) => switch (m.type) {
      PaymentMethodType.carteBancaire =>
        'Carte •••• ${m.quatreDerniersChiffres ?? '----'}',
      PaymentMethodType.portefeuille => 'Portefeuille ProxiLife',
      PaymentMethodType.especes => 'Espèces',
    };

// ------------------------------------------------------------- async view

/// Error state with a « Réessayer » button.
class CoachErrorRetry extends StatelessWidget {
  const CoachErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 48)),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three async states of every CoachProche screen (loading / error with
/// retry / content), so screens don't repeat the same FutureBuilder code.
class CoachAsyncView<T> extends StatelessWidget {
  const CoachAsyncView({
    super.key,
    required this.future,
    required this.onRetry,
    required this.builder,
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CoachErrorRetry(
            message: coachErrorMessage(snapshot.error!),
            onRetry: onRetry,
          );
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}

// ------------------------------------------------------------------ chips

/// Tinted pill (10 % background, coloured label, 35 % border).
class CoachChip extends StatelessWidget {
  const CoachChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.darkText = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Required on light backgrounds for warning-like colours.
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final fg = darkText ? AppColors.text : color;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status of a booking: en attente (info), confirmée (success), présent
/// (violet), annulée (error).
class CoachBookingStatusChip extends StatelessWidget {
  const CoachBookingStatusChip(this.status, {super.key});

  final CoachBookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      CoachBookingStatus.enAttente => (AppColors.info, Icons.schedule),
      CoachBookingStatus.confirmee => (
          AppColors.success,
          Icons.check_circle_outline
        ),
      CoachBookingStatus.present => (
          CoachColors.brandDeep,
          Icons.how_to_reg_outlined
        ),
      CoachBookingStatus.annulee => (AppColors.error, Icons.cancel_outlined),
    };
    return CoachChip(label: status.label, color: color, icon: icon);
  }
}

/// Level of a session ("Débutant"...) as a neutral violet chip.
class CoachLevelChip extends StatelessWidget {
  const CoachLevelChip(this.level, {super.key});

  final CoachLevel level;

  @override
  Widget build(BuildContext context) => CoachChip(
        label: level.label,
        color: CoachColors.brandDeep,
        icon: Icons.signal_cellular_alt,
      );
}

// ----------------------------------------------------------- small pieces

/// Round tinted icon of a sport type.
class CoachTypeAvatar extends StatelessWidget {
  const CoachTypeAvatar(this.type, {super.key, this.size = 48});

  final CoachSessionType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CoachColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(coachTypeIcon(type),
          color: CoachColors.brandDeep, size: size * 0.5),
    );
  }
}

/// "icon  text" line used in cards and detail screens.
class CoachInfoRow extends StatelessWidget {
  const CoachInfoRow({
    super.key,
    required this.icon,
    required this.text,
    this.strong = false,
  });

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondaryStrong),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: strong
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.text, fontWeight: FontWeight.w600)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title used on detail screens.
class CoachSectionTitle extends StatelessWidget {
  const CoachSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
            top: AppSpacing.lg, bottom: AppSpacing.xs),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Big number + caption (steps, heart rate, places...).
class CoachStatTile extends StatelessWidget {
  const CoachStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: CoachColors.brandSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Icon(icon, color: CoachColors.brandDeep, size: 22),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- session card

/// One session in a list (search results, « Mes séances »).
class CoachSessionCard extends StatelessWidget {
  const CoachSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.showCoach = true,
    this.trailing,
  });

  final CoachSessionDto session;
  final VoidCallback onTap;

  /// Hide the coach's name on the coach's own list.
  final bool showCoach;

  /// Extra chip(s) appended to the chip row (e.g. inscrits).
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final distance = s.distanceKm;
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
                  CoachTypeAvatar(s.type),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.titre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        Text(
                          showCoach
                              ? '${s.type.label} · ${s.coachNom}'
                              : s.type.label,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    coachPrice(s.prixCentimes),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: CoachColors.brandDeep,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              CoachInfoRow(
                icon: Icons.event_outlined,
                text: '${coachWhen(s.dateHeure)} · ${coachDuration(s.dureeMinutes)}',
              ),
              CoachInfoRow(
                icon: Icons.place_outlined,
                text: distance == null
                    ? s.lieu
                    : '${s.lieu} · à ${coachDistance(distance)}',
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  CoachLevelChip(s.niveau),
                  if (s.isCancelled)
                    const CoachChip(
                        label: 'Annulée',
                        color: AppColors.error,
                        icon: Icons.cancel_outlined)
                  else if (s.isFull)
                    const CoachChip(
                        label: 'Complet',
                        color: AppColors.warning,
                        darkText: true,
                        icon: Icons.group_off_outlined)
                  else
                    CoachChip(
                        label: coachPlaces(s),
                        color: AppColors.success,
                        icon: Icons.group_outlined),
                  if (s.dejaReserve)
                    const CoachChip(
                        label: 'Réservée',
                        color: AppColors.info,
                        icon: Icons.check_circle_outline),
                  ...?trailing,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
