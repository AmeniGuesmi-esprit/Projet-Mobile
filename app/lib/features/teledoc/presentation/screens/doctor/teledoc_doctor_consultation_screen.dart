import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../widgets/teledoc_submit_button.dart';
import '../../../data/url_launcher_link_opener.dart';
import '../../../domain/teledoc_call.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_call_panel.dart';
import '../../widgets/teledoc_chips.dart';
import '../../widgets/teledoc_photo.dart';

/// Consultation + the request it answers (description and photo).
class _ConsultationData {
  const _ConsultationData(this.consultation, this.request);

  final TeledocConsultationDto consultation;
  final TeledocRequestDto request;
}

enum _MenuAction { absent, requeue }

/// Doctor: runs a consultation (prescription required to end it — use case
/// « include : rédiger l'ordonnance »), or reviews / corrects a finished one.
/// A finished consultation can be edited, never deleted (D10).
class TeledocDoctorConsultationScreen extends StatefulWidget {
  const TeledocDoctorConsultationScreen({
    super.key,
    required this.repository,
    required this.consultationId,
    this.linkOpener = const UrlLauncherLinkOpener(),
  });

  final TeledocRepository repository;
  final int consultationId;

  /// Opens the Jitsi call (faked in tests).
  final TeledocLinkOpener linkOpener;

  @override
  State<TeledocDoctorConsultationScreen> createState() =>
      _TeledocDoctorConsultationScreenState();
}

class _TeledocDoctorConsultationScreenState
    extends State<TeledocDoctorConsultationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ordonnance = TextEditingController();
  late Future<_ConsultationData> _future;

  /// Finished consultation: the prescription is shown read-only until the
  /// doctor chooses to correct it.
  bool _editingFinished = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _ordonnance.dispose();
    super.dispose();
  }

  Future<_ConsultationData> _load() async {
    final consultation = await widget.repository.consultation(
      widget.consultationId,
    );
    final request = await widget.repository.request(consultation.idDemande);
    _ordonnance.text = consultation.ordonnance ?? _ordonnance.text;
    return _ConsultationData(consultation, request);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  /// Runs [action] with the busy flag and a French error snackbar.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) showTeledocSnack(context, teledocErrorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(TeledocConsultationDto c) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await _run(
      () => widget.repository.endConsultation(c.id, _ordonnance.text.trim()),
    );
    if (ok && mounted) {
      showTeledocSnack(context, 'Consultation terminée, ordonnance envoyée');
      _reload();
    }
  }

  Future<void> _saveCorrection(TeledocConsultationDto c) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await _run(
      () => widget.repository.updateConsultation(
        c.id,
        ordonnance: _ordonnance.text.trim(),
      ),
    );
    if (ok && mounted) {
      setState(() => _editingFinished = false);
      showTeledocSnack(context, 'Ordonnance corrigée');
      _reload();
    }
  }

  Future<void> _switchType(TeledocConsultationDto c) async {
    final target = c.type == TeledocConsultationType.video
        ? TeledocConsultationType.audio
        : TeledocConsultationType.video;
    final ok = await _run(
      () => widget.repository.updateConsultation(c.id, type: target),
    );
    if (ok && mounted) _reload();
  }

  Future<void> _menu(_MenuAction action, _ConsultationData data) async {
    final (title, message, confirm) = switch (action) {
      _MenuAction.absent => (
        'Patient absent ?',
        'La demande sera annulée et le patient remboursé.',
        'Annuler la demande',
      ),
      _MenuAction.requeue => (
        'Remettre en file ?',
        'La consultation sera supprimée et le patient retrouvera sa place '
            'dans la file.',
        'Remettre en file',
      ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _run(
      () => switch (action) {
        _MenuAction.absent => widget.repository.cancelRequest(data.request.id),
        _MenuAction.requeue => widget.repository.deleteConsultation(
          data.consultation.id,
        ),
      },
    );
    if (ok && mounted) {
      showTeledocSnack(
        context,
        action == _MenuAction.absent
            ? 'Demande annulée, patient remboursé'
            : 'Patient remis en file',
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ConsultationData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final inProgress = data != null && !data.consultation.estTerminee;
        return Scaffold(
          appBar: AppBar(
            title: Text(inProgress ? 'Consultation en cours' : 'Consultation'),
            actions: [
              if (inProgress)
                PopupMenuButton<_MenuAction>(
                  enabled: !_busy,
                  onSelected: (a) => _menu(a, data),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _MenuAction.absent,
                      child: Text('Patient absent (annuler)'),
                    ),
                    PopupMenuItem(
                      value: _MenuAction.requeue,
                      child: Text('Remettre en file'),
                    ),
                  ],
                ),
            ],
          ),
          body: TeledocAsyncView<_ConsultationData>(
            future: _future,
            onRetry: _reload,
            builder: (context, data) => _body(context, data),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, _ConsultationData data) {
    final theme = Theme.of(context);
    final c = data.consultation;
    final request = data.request;
    final inProgress = !c.estTerminee;
    final interrupted =
        c.estTerminee && c.statutDemande == TeledocRequestStatus.annulee;
    final editable = inProgress || _editingFinished;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // Not a lazy ListView: the prescription field must stay mounted to be
      // validated (D27).
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.patientNom ?? '', style: theme.textTheme.headlineMedium),
            Text(c.motif, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                TeledocStatusChip(c.statutDemande),
                TeledocUrgencyChip(c.urgence),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (inProgress)
              TeledocCallPanel(
                room: c.salleAppel,
                type: c.type,
                opener: widget.linkOpener,
                displayName: c.medecinNom == null ? null : 'Dr ${c.medecinNom}',
                isDoctor: true,
                trailing: TextButton(
                  onPressed: _busy ? null : () => _switchType(c),
                  child: Text(
                    c.type == TeledocConsultationType.video
                        ? 'Passer en audio'
                        : 'Passer en vidéo',
                  ),
                ),
                details: [TeledocInfoRow('Début', teledocDate(c.dateDebut))],
              )
            else
              TeledocSection(
                title: 'Appel',
                child: Column(
                  children: [
                    TeledocInfoRow('Type', c.type.label),
                    TeledocInfoRow('Début', teledocDate(c.dateDebut)),
                    TeledocInfoRow(
                      'Durée',
                      teledocDuration(c.dateDebut, c.dateFin),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TeledocSection(
              title: 'Symptômes décrits',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.description, style: theme.textTheme.bodyLarge),
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
            if (interrupted)
              const TeledocSection(
                title: 'Ordonnance',
                child: Text(
                  'Consultation interrompue (patient absent) : '
                  'aucune ordonnance.',
                ),
              )
            else
              TeledocSection(
                title: 'Ordonnance',
                trailing: c.estTerminee && !_editingFinished
                    ? TextButton.icon(
                        onPressed: () =>
                            setState(() => _editingFinished = true),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Corriger'),
                      )
                    : null,
                child: editable
                    ? TextFormField(
                        controller: _ordonnance,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          hintText: 'Médicament, posologie, durée, conseils…',
                        ),
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 5,
                        maxLines: 12,
                        maxLength: 2000,
                        validator: teledocOrdonnanceError,
                      )
                    : Text(
                        c.ordonnance ?? '—',
                        style: theme.textTheme.bodyLarge,
                      ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (inProgress)
              TeledocSubmitButton(
                label: 'Terminer et envoyer l\'ordonnance',
                icon: Icons.check,
                isLoading: _busy,
                onPressed: () => _end(c),
              )
            else if (_editingFinished) ...[
              TeledocSubmitButton(
                label: 'Enregistrer la correction',
                icon: Icons.save_outlined,
                isLoading: _busy,
                onPressed: () => _saveCorrection(c),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _editingFinished = false;
                        _ordonnance.text = c.ordonnance ?? '';
                      }),
                child: const Text('Annuler la correction'),
              ),
            ] else if (!interrupted)
              Text(
                'Une consultation terminée fait partie du dossier médical : '
                'l\'ordonnance peut être corrigée, la consultation ne peut '
                'pas être supprimée.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
