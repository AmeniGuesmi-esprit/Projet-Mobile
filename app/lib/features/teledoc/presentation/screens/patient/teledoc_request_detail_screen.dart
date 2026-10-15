import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/session/session_controller.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/money_text.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_chips.dart';
import '../../widgets/teledoc_photo.dart';
import 'teledoc_consultation_detail_screen.dart';
import 'teledoc_queue_screen.dart';
import 'teledoc_request_form_screen.dart';

/// Patient: one request, with the actions its status allows
/// (TeledocRequestRules is the single source of truth).
class TeledocRequestDetailScreen extends StatefulWidget {
  const TeledocRequestDetailScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.requestId,
  });

  final SessionController session;
  final TeledocRepository repository;
  final int requestId;

  @override
  State<TeledocRequestDetailScreen> createState() =>
      _TeledocRequestDetailScreenState();
}

class _TeledocRequestDetailScreenState
    extends State<TeledocRequestDetailScreen> {
  late Future<TeledocRequestDto> _future;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.request(widget.requestId);
  }

  void _reload() => setState(() {
    _future = widget.repository.request(widget.requestId);
  });

  Future<void> _edit(TeledocRequestDto request) async {
    final saved = await Navigator.of(context).push<TeledocRequestDto>(
      MaterialPageRoute(
        builder: (_) => TeledocRequestFormScreen(
          session: widget.session,
          repository: widget.repository,
          initial: request,
        ),
      ),
    );
    if (saved != null && mounted) {
      _reload();
      showTeledocSnack(context, 'Demande mise à jour');
    }
  }

  Future<void> _cancel(TeledocRequestDto request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        content: Text(
          'Vous quitterez la file d\'attente. '
          '${MoneyText.format(TeledocPricing.consultationCents)} vous seront '
          'remboursés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder ma place'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annuler la demande'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await widget.repository.cancelRequest(request.id);
      if (!mounted) return;
      showTeledocSnack(context, 'Demande annulée et remboursée');
      _reload();
    } catch (e) {
      if (mounted) showTeledocSnack(context, teledocErrorMessage(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ma demande')),
      body: TeledocAsyncView<TeledocRequestDto>(
        future: _future,
        onRetry: _reload,
        builder: (context, request) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _header(context, request),
              const SizedBox(height: AppSpacing.md),
              ..._statusBlock(context, request),
              TeledocSection(
                title: 'Symptômes',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (request.aPhoto) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TeledocRequestPhoto(
                        repository: widget.repository,
                        request: request,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TeledocSection(
                title: 'Informations',
                child: Column(
                  children: [
                    TeledocInfoRow('Créée le', teledocDate(request.creeLe)),
                    TeledocInfoRow(
                      'Modifiée le',
                      teledocDate(request.modifieLe),
                    ),
                    TeledocInfoRow(
                      'Paiement',
                      request.transactionId == null
                          ? 'Aucun'
                          : MoneyText.format(TeledocPricing.consultationCents),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ..._actions(request),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, TeledocRequestDto request) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(request.motif, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            TeledocStatusChip(request.statut),
            TeledocUrgencyChip(request.urgence),
          ],
        ),
      ],
    );
  }

  /// Queue position (waiting) or consultation info (started / finished).
  List<Widget> _statusBlock(BuildContext context, TeledocRequestDto request) {
    final theme = Theme.of(context);
    final Widget? block = switch (request.statut) {
      TeledocRequestStatus.enAttente when request.positionFile != null =>
        TeledocSection(
          title: 'File d\'attente',
          child: Row(
            children: [
              Expanded(
                child: TeledocInfoRow(
                  'Position',
                  teledocPositionLabel(request.positionFile!),
                ),
              ),
              Expanded(
                child: Text(
                  teledocWaitLabel(request.tempsEstimeMinutes),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      TeledocRequestStatus.enCours => TeledocSection(
        title: 'Consultation en cours',
        child: Text(
          'Un médecin a pris en charge votre demande.',
          style: theme.textTheme.bodyLarge,
        ),
      ),
      _ => null,
    };
    return block == null
        ? const []
        : [block, const SizedBox(height: AppSpacing.md)];
  }

  List<Widget> _actions(TeledocRequestDto request) {
    final consultationId = request.consultationId;
    return [
      if (request.statut == TeledocRequestStatus.enAttente ||
          request.statut == TeledocRequestStatus.enCours) ...[
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => TeledocQueueScreen(
                session: widget.session,
                repository: widget.repository,
                requestId: request.id,
              ),
            ),
          ),
          icon: Icon(
            request.statut == TeledocRequestStatus.enCours
                ? Icons.videocam_outlined
                : Icons.groups_outlined,
          ),
          label: Text(
            request.statut == TeledocRequestStatus.enCours
                ? "Rejoindre l'appel"
                : 'Suivre la file en direct',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (TeledocRequestRules.canEdit(request.statut))
        OutlinedButton.icon(
          onPressed: _cancelling ? null : () => _edit(request),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Modifier'),
        ),
      if (TeledocRequestRules.canTransition(
        request.statut,
        TeledocRequestStatus.annulee,
        TeledocActor.patient,
      )) ...[
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: _cancelling ? null : () => _cancel(request),
          icon: _cancelling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.close),
          label: const Text('Annuler la demande'),
        ),
      ],
      if (request.statut == TeledocRequestStatus.terminee &&
          consultationId != null)
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
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
  }
}
