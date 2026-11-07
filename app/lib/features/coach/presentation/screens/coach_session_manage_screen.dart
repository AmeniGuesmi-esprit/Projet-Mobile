import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/live/live_refresh.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';
import 'coach_scan_screen.dart';
import 'coach_session_form_screen.dart';

/// Coach: one of my sessions with its participants; scan, edit or cancel.
class CoachSessionManageScreen extends StatefulWidget {
  const CoachSessionManageScreen({
    super.key,
    required this.session,
    required this.sessionId,
  });

  final SessionController session;
  final int sessionId;

  @override
  State<CoachSessionManageScreen> createState() =>
      _CoachSessionManageScreenState();
}

typedef _Data = (CoachSessionDto, List<CoachBookingDto>);

class _CoachSessionManageScreenState extends State<CoachSessionManageScreen>
    with LiveRefresh<CoachSessionManageScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late Future<_Data> _future = _fetch();
  bool _busy = false;

  Future<_Data> _fetch() async {
    final s = await _api.getSession(widget.sessionId);
    final attendees = await _api.attendees(widget.sessionId);
    return (s, attendees);
  }

  @override
  Future<void> liveRefresh() async {
    final data = await _fetch();
    if (!mounted) return;
    setState(() {
      _future = liveFuture(data);
    });
  }

  void _reload() => setState(() {
        _future = _fetch();
      });

  Future<void> _scan() async {
    await pushCoach<void>(context, CoachScanScreen(session: widget.session));
    if (mounted) _reload();
  }

  Future<void> _edit(CoachSessionDto s) async {
    final saved = await pushCoach<bool>(
      context,
      CoachSessionFormScreen(session: widget.session, existing: s),
    );
    if (saved == true && mounted) {
      _reload();
      showCoachSnack(context, 'Séance modifiée');
    }
  }

  Future<void> _cancelSession(CoachSessionDto s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.event_busy_outlined, color: AppColors.error),
        title: const Text('Annuler cette séance ?'),
        content: Text(
          s.inscrits == 0
              ? 'La séance ne sera plus proposée aux clients.'
              : '${s.inscrits} participant${s.inscrits > 1 ? 's seront prévenus et remboursés' : ' sera prévenu et remboursé'}. '
                  'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder la séance'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(120, 48),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annuler la séance'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.cancelSession(s.id);
      if (!mounted) return;
      setState(() => _busy = false);
      _reload();
      showCoachSnack(context, 'Séance annulée, les participants sont prévenus');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showCoachSnack(context, coachErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ma séance')),
      body: CoachAsyncView<_Data>(
        future: _future,
        onRetry: _reload,
        builder: _content,
      ),
    );
  }

  Widget _content(BuildContext context, _Data data) {
    final theme = Theme.of(context);
    final (s, attendees) = data;
    final now = DateTime.now();
    final started = !s.dateHeure.isAfter(now);
    final canManage = !s.isCancelled && !started;
    final canScan = !s.isCancelled && s.fin.isAfter(now);
    final present =
        attendees.where((a) => a.statut == CoachBookingStatus.present).length;
    return RefreshIndicator(
      color: CoachColors.brandDeep,
      onRefresh: () async {
        _reload();
        await _future.catchError((_) => (s, attendees));
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: CoachColors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CoachTypeAvatar(s.type, size: 56),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(s.titre, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
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
                    else if (!s.fin.isAfter(now))
                      const CoachChip(
                          label: 'Terminée',
                          color: AppColors.textSecondaryStrong,
                          icon: Icons.flag_outlined)
                    else if (started)
                      const CoachChip(
                          label: 'En cours',
                          color: AppColors.success,
                          icon: Icons.play_circle_outline),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                CoachInfoRow(
                  icon: Icons.event_outlined,
                  text: '${coachDay(s.dateHeure)} · '
                      '${coachRange(s.dateHeure, s.dureeMinutes)}',
                  strong: true,
                ),
                CoachInfoRow(icon: Icons.place_outlined, text: s.lieu),
                CoachInfoRow(
                    icon: Icons.payments_outlined,
                    text: '${coachPrice(s.prixCentimes)} par participant'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: CoachStatTile(
                  icon: Icons.groups_outlined,
                  value: '${s.inscrits}/${s.placesTotales}',
                  label: 'inscrits',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: CoachStatTile(
                  icon: Icons.how_to_reg_outlined,
                  value: '$present',
                  label: 'présents',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: CoachStatTile(
                  icon: Icons.event_seat_outlined,
                  value: '${s.placesRestantes}',
                  label: 'places libres',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (canScan)
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner les présences'),
            ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _edit(s),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier la séance'),
            ),
          ],
          CoachSectionTitle('Participants (${attendees.length})'),
          if (attendees.isEmpty)
            Text('Aucun inscrit pour le moment.',
                style: theme.textTheme.bodyMedium)
          else
            for (final a in attendees)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _AttendeeCard(booking: a),
              ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.lg),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _busy ? null : () => _cancelSession(s),
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Annuler la séance'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _AttendeeCard extends StatelessWidget {
  const _AttendeeCard({required this.booking});

  final CoachBookingDto booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = booking;
    final extras = <String>[
      if (b.pas != null) '${b.pas} pas',
      if (b.frequenceCardiaque != null) '${b.frequenceCardiaque} BPM',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: CoachColors.brandSoft,
              child: Icon(Icons.person_outline, color: CoachColors.brandDeep),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.clientNom, style: theme.textTheme.titleMedium),
                  if (extras.isNotEmpty)
                    Text(extras.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CoachBookingStatusChip(b.statut),
                if (b.statutPaiement != null &&
                    b.montantCentimes > 0 &&
                    b.statutPaiement != TransactionStatus.paye) ...[
                  const SizedBox(height: 4),
                  StatusChip(b.statutPaiement!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
