import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/session/session_controller.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/service_badge.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_chips.dart';
import 'teledoc_consultation_detail_screen.dart';
import 'teledoc_queue_screen.dart';
import 'teledoc_request_detail_screen.dart';
import 'teledoc_request_form_screen.dart';
import 'teledoc_pharmacy_screen.dart';
import '../../teledoc_theme.dart';

/// Patient space: requests (with the active one highlighted) and the
/// consultation history (prescriptions).
class TeledocPatientHomeScreen extends StatefulWidget {
  const TeledocPatientHomeScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final TeledocRepository repository;

  @override
  State<TeledocPatientHomeScreen> createState() =>
      _TeledocPatientHomeScreenState();
}

class _TeledocPatientHomeScreenState extends State<TeledocPatientHomeScreen> {
  late Future<List<TeledocRequestDto>> _requests;
  late Future<List<TeledocConsultationDto>> _consultations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requests = widget.repository.myRequests();
    _consultations = widget.repository.consultations();
  }

  void _reload() => setState(_load);

  Future<void> _openForm() async {
    final created = await Navigator.of(context).push<TeledocRequestDto>(
      TeledocPageRoute(
        builder: (_) => TeledocRequestFormScreen(
          session: widget.session,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
    if (created != null) {
      // Straight to the live queue: the patient sees their position.
      await _openQueue(created);
    }
  }

  Future<void> _openQueue(TeledocRequestDto request) async {
    await Navigator.of(context).push<void>(
      TeledocPageRoute(
        builder: (_) => TeledocQueueScreen(
          session: widget.session,
          repository: widget.repository,
          requestId: request.id,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openRequest(TeledocRequestDto request) async {
    await Navigator.of(context).push<void>(
      TeledocPageRoute(
        builder: (_) => TeledocRequestDetailScreen(
          session: widget.session,
          repository: widget.repository,
          requestId: request.id,
        ),
      ),
    );
    if (mounted) _reload();
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
              tooltip: 'Pharmacies de garde',
              icon: const Icon(Icons.local_pharmacy_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                TeledocPageRoute(
                  builder: (_) =>
                      TeledocPharmacyScreen(repository: widget.repository),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mes demandes'),
              Tab(text: 'Mes consultations'),
            ],
          ),
        ),
        body: TabBarView(children: [_requestsTab(), _consultationsTab()]),
      ),
    );
  }

  Widget _requestsTab() {
    return TeledocAsyncView<List<TeledocRequestDto>>(
      future: _requests,
      onRetry: _reload,
      builder: (context, requests) {
        final active = requests
            .where((r) => TeledocRequestRules.isActive(r.statut))
            .firstOrNull;
        final past = requests.where((r) => r != active).toList();
        return RefreshIndicator(
          color: TeledocColors.brandDeep,
          onRefresh: () async {
            _reload();
            await _requests;
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (active != null)
                _ActiveRequestCard(
                  request: active,
                  onOpen: () => active.statut == TeledocRequestStatus.enAttente
                      ? _openQueue(active)
                      : _openRequest(active),
                )
              else
                _NewRequestCard(onCreate: _openForm),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Historique des demandes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              if (past.isEmpty)
                const EmptyState(
                  icon: Icons.history,
                  title: 'Aucune demande passée',
                  color: AppColors.moduleTeleDoc,
                )
              else
                for (final request in past)
                  _RequestTile(
                    request: request,
                    onTap: () => _openRequest(request),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _consultationsTab() {
    return TeledocAsyncView<List<TeledocConsultationDto>>(
      future: _consultations,
      onRetry: _reload,
      builder: (context, consultations) {
        if (consultations.isEmpty) {
          return const EmptyState(
            icon: Icons.description_outlined,
            title: 'Aucune consultation',
            message:
                'Vos ordonnances apparaîtront ici après chaque '
                'consultation.',
            color: AppColors.moduleTeleDoc,
          );
        }
        return RefreshIndicator(
          color: TeledocColors.brandDeep,
          onRefresh: () async {
            _reload();
            await _consultations;
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: consultations.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final c = consultations[i];
              return Card(
                child: ListTile(
                  leading: Icon(
                    c.type == TeledocConsultationType.audio
                        ? Icons.call_outlined
                        : Icons.videocam_outlined,
                    color: TeledocColors.brandDeep,
                  ),
                  title: Text(c.motif),
                  subtitle: Text(
                    '${teledocDate(c.dateDebut)} · Dr ${c.medecinNom ?? '—'}',
                  ),
                  trailing: TeledocStatusChip(c.statutDemande),
                  onTap: () => Navigator.of(context).push<void>(
                    TeledocPageRoute(
                      builder: (_) => TeledocConsultationDetailScreen(
                        repository: widget.repository,
                        consultationId: c.id,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _NewRequestCard extends StatelessWidget {
  const _NewRequestCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Besoin d\'un médecin ?', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Décrivez vos symptômes, ajoutez une photo si besoin : un '
              'médecin vous rappelle en audio ou en vidéo.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle demande'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.request, required this.onOpen});

  final TeledocRequestDto request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = request.statut == TeledocRequestStatus.enAttente;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Demande en cours',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TeledocStatusChip(request.statut),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(request.motif, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (waiting && request.positionFile != null)
                Text(
                  'Vous êtes ${teledocPositionLabel(request.positionFile!)} '
                  'dans la file · ${teledocWaitLabel(request.tempsEstimeMinutes)}',
                  style: theme.textTheme.bodyLarge,
                )
              else if (!waiting)
                Text(
                  'Le médecin a commencé votre consultation.',
                  style: theme.textTheme.bodyLarge,
                ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(waiting ? Icons.groups_outlined : Icons.videocam),
                label: Text(waiting ? 'Suivre ma demande' : 'Voir ma demande'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onTap});

  final TeledocRequestDto request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Card(
        child: ListTile(
          title: Text(request.motif),
          subtitle: Text(teledocDate(request.creeLe)),
          trailing: TeledocStatusChip(request.statut),
          onTap: onTap,
        ),
      ),
    );
  }
}
