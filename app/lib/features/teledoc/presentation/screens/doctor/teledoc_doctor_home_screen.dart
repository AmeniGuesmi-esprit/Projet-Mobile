import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/service_badge.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_chips.dart';
import '../../widgets/teledoc_photo.dart';
import 'teledoc_doctor_consultation_screen.dart';

/// What the doctor's queue tab needs: the queue and their own consultations
/// (to detect the one in progress).
class _DoctorDashboard {
  const _DoctorDashboard(this.queue, this.consultations);

  final List<TeledocRequestDto> queue;
  final List<TeledocConsultationDto> consultations;

  TeledocConsultationDto? get current =>
      consultations.where((c) => !c.estTerminee).firstOrNull;
}

/// Doctor space: the shared waiting queue (always served head first, D4)
/// and the history of their consultations.
class TeledocDoctorHomeScreen extends StatefulWidget {
  const TeledocDoctorHomeScreen({super.key, required this.repository});

  final TeledocRepository repository;

  @override
  State<TeledocDoctorHomeScreen> createState() =>
      _TeledocDoctorHomeScreenState();
}

class _TeledocDoctorHomeScreenState extends State<TeledocDoctorHomeScreen> {
  late Future<_DoctorDashboard> _future;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DoctorDashboard> _load() async {
    final results = await Future.wait([
      widget.repository.waitingQueue(),
      widget.repository.consultations(),
    ]);
    return _DoctorDashboard(
      results[0] as List<TeledocRequestDto>,
      results[1] as List<TeledocConsultationDto>,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openConsultation(int id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeledocDoctorConsultationScreen(
          repository: widget.repository,
          consultationId: id,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _startNext() async {
    final type = await showModalBottomSheet<TeledocConsultationType>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('Type de consultation'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.primary),
              title: const Text('Vidéo'),
              onTap: () =>
                  Navigator.pop(sheetContext, TeledocConsultationType.video),
            ),
            ListTile(
              leading: const Icon(Icons.call, color: AppColors.primary),
              title: const Text('Audio'),
              onTap: () =>
                  Navigator.pop(sheetContext, TeledocConsultationType.audio),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _starting = true);
    try {
      final consultation = await widget.repository.startNextConsultation(type);
      if (!mounted) return;
      setState(() => _starting = false);
      await _openConsultation(consultation.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      showTeledocSnack(context, teledocErrorMessage(e));
      _reload(); // the queue may have changed (another doctor was faster)
    }
  }

  void _preview(TeledocRequestDto request) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.motif,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [TeledocUrgencyChip(request.urgence)],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                request.description,
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
              if (request.aPhoto) ...[
                const SizedBox(height: AppSpacing.sm),
                TeledocRequestPhoto(
                  repository: widget.repository,
                  request: request,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Les demandes sont prises dans l\'ordre de la file '
                '(urgence puis arrivée).',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const ServiceBadge(ServiceType.teleDoc),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'File d\'attente'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: TeledocAsyncView<_DoctorDashboard>(
          future: _future,
          onRetry: _reload,
          builder: (context, data) =>
              TabBarView(children: [_queueTab(data), _historyTab(data)]),
        ),
      ),
    );
  }

  Widget _queueTab(_DoctorDashboard data) {
    final theme = Theme.of(context);
    final current = data.current;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        _reload();
        await _future;
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (current != null)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(AppSpacing.md),
                leading: const Icon(
                  Icons.medical_services,
                  color: AppColors.primary,
                ),
                title: const Text('Consultation en cours'),
                subtitle: Text('${current.patientNom} · ${current.motif}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openConsultation(current.id),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      data.queue.isEmpty
                          ? 'Aucun patient en attente'
                          : '${data.queue.length} patient'
                                '${data.queue.length > 1 ? 's' : ''} '
                                'en attente',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: data.queue.isEmpty || _starting
                          ? null
                          : _startNext,
                      icon: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Démarrer la prochaine consultation'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (data.queue.isEmpty)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'La file est vide',
              message: 'Tirez vers le bas pour actualiser.',
              color: AppColors.moduleTeleDoc,
            )
          else
            for (final request in data.queue)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.moduleTeleDoc.withValues(
                        alpha: 0.10,
                      ),
                      foregroundColor: AppColors.moduleTeleDoc,
                      child: Text('${request.positionFile ?? '?'}'),
                    ),
                    title: Text(request.motif),
                    subtitle: Text(
                      '${request.patientNom ?? ''} · '
                      '${teledocWaitLabel(request.tempsEstimeMinutes)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (request.aPhoto)
                          const Padding(
                            padding: EdgeInsets.only(right: AppSpacing.xxs),
                            child: Icon(
                              Icons.photo_outlined,
                              size: 18,
                              semanticLabel: 'Photo jointe',
                            ),
                          ),
                        TeledocUrgencyChip(request.urgence),
                      ],
                    ),
                    onTap: () => _preview(request),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _historyTab(_DoctorDashboard data) {
    if (data.consultations.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'Aucune consultation',
        message: 'Vos consultations apparaîtront ici.',
        color: AppColors.moduleTeleDoc,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: data.consultations.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final c = data.consultations[i];
        return Card(
          child: ListTile(
            title: Text('${c.patientNom ?? ''} · ${c.motif}'),
            subtitle: Text(
              '${teledocDate(c.dateDebut)} · ${c.type.label} · '
              '${teledocDuration(c.dateDebut, c.dateFin)}',
            ),
            trailing: TeledocStatusChip(c.statutDemande),
            onTap: () => _openConsultation(c.id),
          ),
        );
      },
    );
  }
}
