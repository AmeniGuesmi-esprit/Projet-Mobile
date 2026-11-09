import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/live/live_refresh.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'demande_detail_screen.dart';
import 'widgets/service_now_widgets.dart';

/// A list of requests, kept up to date; opens the detail screen on tap.
class DemandeListView extends StatefulWidget {
  const DemandeListView({
    super.key,
    required this.session,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final SessionController session;
  final Future<List<DemandeServiceDto>> Function() load;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<DemandeListView> createState() => _DemandeListViewState();
}

class _DemandeListViewState extends State<DemandeListView>
    with LiveRefresh<DemandeListView> {
  late Future<List<DemandeServiceDto>> _future = widget.load();

  /// Status shown by the client's filter; null shows every request.
  DemandeServiceStatus? _filter;

  /// Prestataires already have their lists split by tabs.
  bool get _showFilter => widget.session.user?.role != UserRole.prestataire;

  @override
  Future<void> liveRefresh() async {
    final items = await widget.load();
    if (!mounted) return;
    setState(() => _future = liveFuture(items));
  }

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _open(DemandeServiceDto demande) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DemandeDetailScreen(session: widget.session, demande: demande),
      ),
    );
    if (mounted) await _reload();
  }

  /// A centred message that can still be pulled down to refresh.
  Widget _message(Widget child) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [const SizedBox(height: AppSpacing.xxl), child],
      );

  Widget _filterChip(String label, DemandeServiceStatus? status) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: ChoiceChip(
          label: Text(label),
          showCheckmark: false,
          selected: _filter == status,
          onSelected: (_) => setState(() => _filter = status),
        ),
      );

  Widget _filterBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: Row(
          children: [
            _filterChip('Toutes', null),
            for (final status in DemandeServiceStatus.values)
              _filterChip(status.label, status),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _reload,
      child: FutureBuilder<List<DemandeServiceDto>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Chargement impossible',
              message: '${apiErrorMessage(snapshot.error!)}'
                  '\nTirez vers le bas pour réessayer.',
              color: AppColors.error,
            ));
          }
          final all = snapshot.data ?? const <DemandeServiceDto>[];
          final filter = _filter;
          final items = filter == null
              ? all
              : all.where((d) => d.statut == filter).toList();
          if (all.isEmpty) {
            return _message(EmptyState(
              icon: widget.emptyIcon,
              title: widget.emptyTitle,
              message: widget.emptyMessage,
            ));
          }
          if (items.isEmpty) {
            return _message(EmptyState(
              icon: Icons.filter_list_off,
              title: 'Aucune demande dans ce statut',
              message: 'Choisissez un autre filtre.',
            ));
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            // Leaves room for the "Nouvelle demande" button.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              96,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => DemandeCard(
              demande: items[i],
              onTap: () => _open(items[i]),
            ),
          );
        },
      ),
    );
    if (!_showFilter) return list;
    return Column(
      children: [
        _filterBar(),
        Expanded(child: list),
      ],
    );
  }
}
