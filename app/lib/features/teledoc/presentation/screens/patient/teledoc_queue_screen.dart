import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/session/session_controller.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/service_badge.dart';
import '../../../data/teledoc_local_queue_notifier.dart';
import '../../../data/url_launcher_link_opener.dart';
import '../../../domain/teledoc_call.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_queue_tracker.dart';
import '../../../domain/teledoc_repository.dart';
import '../../controllers/teledoc_queue_controller.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_call_panel.dart';
import 'teledoc_consultation_detail_screen.dart';
import 'teledoc_request_detail_screen.dart';
import '../../teledoc_theme.dart';

/// Patient: live view of the virtual waiting queue (polling every 5 s).
class TeledocQueueScreen extends StatefulWidget {
  const TeledocQueueScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.requestId,
    this.notifier,
    this.enableNotifications,
    this.pollInterval = const Duration(seconds: 5),
    this.linkOpener = const UrlLauncherLinkOpener(),
  });

  final SessionController session;
  final TeledocRepository repository;
  final int requestId;

  /// Injected in tests; defaults to Android local notifications.
  final TeledocQueueNotifier? notifier;

  /// Injected in tests; defaults to the Android permission request.
  final Future<bool> Function()? enableNotifications;
  final Duration pollInterval;

  /// Opens the Jitsi call (faked in tests).
  final TeledocLinkOpener linkOpener;

  @override
  State<TeledocQueueScreen> createState() => _TeledocQueueScreenState();
}

class _TeledocQueueScreenState extends State<TeledocQueueScreen> {
  late final TeledocQueueController _controller = TeledocQueueController(
    repository: widget.repository,
    requestId: widget.requestId,
    notifier:
        widget.notifier ?? TeledocLocalQueueNotifier(widget.session.settings),
    interval: widget.pollInterval,
  );

  /// Refreshes immediately when the app comes back to the foreground.
  late final AppLifecycleListener _lifecycle;

  bool? _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _controller.start();
    _lifecycle = AppLifecycleListener(onResume: _controller.refresh);
    widget.session.settings.getNotificationsEnabled().then((enabled) {
      if (mounted) setState(() => _notificationsEnabled = enabled);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enableNotifications() async {
    final enable =
        widget.enableNotifications ??
        () => enableTeledocNotifications(widget.session.settings);
    final granted = await enable();
    if (!mounted) return;
    setState(() => _notificationsEnabled = granted);
    showTeledocSnack(
      context,
      granted
          ? 'Vous serez prévenu quand ce sera bientôt votre tour'
          : 'Activez les notifications dans les réglages Android',
    );
  }

  String? get _patientName {
    final user = widget.session.user;
    return user == null ? null : '${user.prenom} ${user.nom}';
  }

  void _openDetails() => Navigator.of(context).push<void>(
    TeledocPageRoute(
      builder: (_) => TeledocRequestDetailScreen(
        session: widget.session,
        repository: widget.repository,
        requestId: widget.requestId,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File d\'attente'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: ServiceBadge(ServiceType.teleDoc, compact: true),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final status = _controller.status;
          if (status == null) {
            return _controller.error == null
                ? const Center(child: CircularProgressIndicator())
                : TeledocErrorRetry(
                    message: _controller.error!,
                    onRetry: _controller.refresh,
                  );
          }
          return RefreshIndicator(
            color: TeledocColors.brandDeep,
            onRefresh: _controller.refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (_controller.error != null) _offlineBanner(context),
                ..._content(context, status),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _offlineBanner(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Material(
      color: AppColors.warning.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: AppColors.text, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Connexion perdue : nouvelle tentative automatique…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _content(BuildContext context, TeledocQueueStatusDto status) {
    final theme = Theme.of(context);
    switch (status.statut) {
      case TeledocRequestStatus.enAttente:
        final position = status.positionFile ?? 1;
        final soon = TeledocQueue.isSoon(position);
        return [
          _PositionCard(
            position: position,
            size: status.taille,
            wait: status.tempsEstimeMinutes,
            soon: soon,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_notificationsEnabled == false)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.notifications_active_outlined,
                  color: TeledocColors.brandDeep,
                ),
                title: const Text('Être prévenu de mon tour'),
                subtitle: const Text(
                  'Une notification quand vous êtes dans les 2 prochains.',
                ),
                trailing: TextButton(
                  onPressed: _enableNotifications,
                  child: const Text('Activer'),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Actualisation automatique toutes les '
            '${widget.pollInterval.inSeconds} s. Gardez l\'application '
            'ouverte : le médecin vous appellera ici.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _openDetails,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Détails, modifier ou annuler'),
          ),
        ];
      case TeledocRequestStatus.enCours:
        return [
          _StateCard(
            icon: status.typeConsultation == TeledocConsultationType.audio
                ? Icons.call
                : Icons.videocam,
            color: TeledocColors.brandDeep,
            title: 'Le médecin vous attend',
            message:
                'Votre consultation '
                '${status.typeConsultation?.label.toLowerCase() ?? ''} '
                "a commencé : rejoignez l'appel.",
          ),
          const SizedBox(height: AppSpacing.md),
          TeledocCallPanel(
            room: status.salleAppel,
            type: status.typeConsultation ?? TeledocConsultationType.video,
            opener: widget.linkOpener,
            displayName: _patientName,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _openDetails,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Voir ma demande'),
          ),
        ];
      case TeledocRequestStatus.terminee:
        final consultationId = status.consultationId;
        return [
          const _StateCard(
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            title: 'Consultation terminée',
            message: 'Votre ordonnance est disponible.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (consultationId != null)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                TeledocPageRoute(
                  builder: (_) => TeledocConsultationDetailScreen(
                    repository: widget.repository,
                    consultationId: consultationId,
                  ),
                ),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Voir l\'ordonnance'),
            ),
        ];
      case TeledocRequestStatus.annulee:
        return [
          const _StateCard(
            icon: Icons.block,
            color: AppColors.textSecondaryStrong,
            title: 'Demande annulée',
            message: 'Le montant de la consultation vous a été remboursé.',
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Retour'),
          ),
        ];
    }
  }
}

/// Big position display. `liveRegion` makes TalkBack announce changes.
class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.size,
    required this.wait,
    required this.soon,
  });

  final int position;
  final int? size;
  final int? wait;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = soon ? AppColors.success : AppColors.moduleTeleDoc;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          liveRegion: true,
          label:
              'Position ${teledocPositionLabel(position)} dans la file. '
              'Attente estimée : ${teledocWaitLabel(wait)}.',
          child: ExcludeSemantics(
            child: Column(
              children: [
                Text('Votre position', style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(position),
                    width: 112,
                    height: 112,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.10),
                      border: Border.all(color: accent, width: 3),
                    ),
                    child: Text(
                      teledocPositionLabel(position),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: accent,
                      ),
                    ),
                  ),
                ),
                if (size != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    size == 1
                        ? 'Seul patient en attente'
                        : 'sur $size patients',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule, size: 20),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      teledocWaitLabel(wait),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                if (soon) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'C\'est bientôt votre tour, restez disponible !',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.success,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          liveRegion: true,
          child: Column(
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
