import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/live/live_refresh.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_widgets.dart';
import 'coach_notifications_screen.dart';
import 'coach_scan_screen.dart';
import 'coach_session_form_screen.dart';
import 'coach_session_manage_screen.dart';

/// Coach home: « Mes séances » (à venir, terminées, annulées), publish a new
/// session and open the QR scanner to validate the presences.
class CoachSessionsScreen extends StatefulWidget {
  const CoachSessionsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CoachSessionsScreen> createState() => _CoachSessionsScreenState();
}

class _CoachSessionsScreenState extends State<CoachSessionsScreen>
    with LiveRefresh<CoachSessionsScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late Future<List<CoachSessionDto>> _future = _api.mySessions();

  @override
  Future<void> liveRefresh() async {
    final items = await _api.mySessions();
    if (!mounted) return;
    setState(() {
      _future = liveFuture(items);
    });
  }

  void _reload() => setState(() {
        _future = _api.mySessions();
      });

  Future<void> _publish() async {
    final saved = await pushCoach<bool>(
      context,
      CoachSessionFormScreen(session: widget.session),
    );
    if (saved == true && mounted) {
      _reload();
      showCoachSnack(context, 'Séance publiée');
    }
  }

  Future<void> _scan() => pushCoach<void>(
        context,
        CoachScanScreen(session: widget.session),
      );

  Future<void> _open(CoachSessionDto s) async {
    await pushCoach<void>(
      context,
      CoachSessionManageScreen(
        session: widget.session,
        sessionId: s.id,
      ),
    );
    if (mounted) _reload();
  }

  Widget _section(BuildContext context, String title, List<CoachSessionDto> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoachSectionTitle('$title (${list.length})'),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: CoachSessionCard(
              session: s,
              showCoach: false,
              onTap: () => _open(s),
              trailing: [
                if (!s.isCancelled)
                  CoachChip(
                    label: '${s.inscrits} inscrit${s.inscrits > 1 ? 's' : ''}',
                    color: AppColors.info,
                    icon: Icons.groups_outlined,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes séances'),
        actions: [
          IconButton(
            tooltip: 'Scanner la présence d\'un client',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          CoachBellButton(session: widget.session),
        ],
      ),
      body: CoachAsyncView<List<CoachSessionDto>>(
        future: _future,
        onRetry: _reload,
        builder: (context, sessions) {
          final now = DateTime.now();
          final upcoming = sessions
              .where((s) => !s.isCancelled && s.fin.isAfter(now))
              .toList()
            ..sort((a, b) => a.dateHeure.compareTo(b.dateHeure));
          final done = sessions
              .where((s) => !s.isCancelled && !s.fin.isAfter(now))
              .toList();
          final cancelled = sessions.where((s) => s.isCancelled).toList();
          return RefreshIndicator(
            color: CoachColors.brandDeep,
            onRefresh: () async {
              _reload();
              await _future.catchError((_) => <CoachSessionDto>[]);
            },
            child: sessions.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: AppSpacing.xl),
                      EmptyState(
                        icon: Icons.fitness_center_outlined,
                        title: 'Aucune séance publiée',
                        message: 'Publiez votre première séance : les clients '
                            'proches de vous pourront la réserver.',
                        color: AppColors.moduleCoachProche,
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, 96),
                    children: [
                      if (upcoming.isNotEmpty)
                        _section(context, 'À venir', upcoming),
                      if (done.isNotEmpty)
                        _section(context, 'Terminées', done),
                      if (cancelled.isNotEmpty)
                        _section(context, 'Annulées', cancelled),
                    ],
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _publish,
        backgroundColor: CoachColors.brandDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Publier une séance'),
      ),
    );
  }
}
