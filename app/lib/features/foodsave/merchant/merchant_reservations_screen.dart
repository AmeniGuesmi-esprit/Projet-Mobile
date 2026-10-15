import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'scan_screen.dart';
import 'widgets/merchant_reservation_tile.dart';
import 'widgets/status_filter_bar.dart';

/// Reservations received by the merchant (all, or one basket's), filterable
/// by status, with live expiry countdowns for the active ones.
class MerchantReservationsScreen extends StatefulWidget {
  const MerchantReservationsScreen(
      {super.key, required this.session, this.basketId});

  final SessionController session;
  final int? basketId;

  @override
  State<MerchantReservationsScreen> createState() =>
      _MerchantReservationsScreenState();
}

class _MerchantReservationsScreenState
    extends State<MerchantReservationsScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late Future<List<ReservationDto>> _future = _load();
  ReservationStatus? _filter;

  static const List<FilterOption<ReservationStatus>> _options = [
    FilterOption(null, 'Toutes'),
    FilterOption(ReservationStatus.enAttente, 'À retirer'),
    FilterOption(ReservationStatus.retire, 'Retirées'),
    FilterOption(ReservationStatus.expire, 'Expirées'),
    FilterOption(ReservationStatus.annule, 'Annulées'),
  ];

  Future<List<ReservationDto>> _load() =>
      _api.merchantReservations(panierId: widget.basketId);

  Future<void> _refresh() {
    final future = _load();
    setState(() => _future = future);
    return future.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.basketId == null
            ? 'Réservations'
            : 'Réservations du panier'),
        actions: [
          IconButton(
            tooltip: 'Scanner un QR code',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ScanScreen(session: widget.session)));
              if (mounted) await _refresh();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ReservationDto>>(
        future: _future,
        builder: (context, snapshot) {
          final Widget child;
          if (snapshot.hasData) {
            child = _content(snapshot.data!);
          } else if (snapshot.hasError) {
            child = FoodSaveErrorView(
                key: const ValueKey('error'),
                error: snapshot.error,
                onRetry: _refresh);
          } else {
            child = const _ReservationsSkeleton(key: ValueKey('loading'));
          }
          return AnimatedSwitcher(
            duration: FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            child: child,
          );
        },
      ),
    );
  }

  Widget _content(List<ReservationDto> all) {
    final counts = <ReservationStatus?, int>{null: all.length};
    for (final r in all) {
      counts[r.statut] = (counts[r.statut] ?? 0) + 1;
    }
    final items =
        _filter == null ? all : all.where((r) => r.statut == _filter).toList();
    return Column(
      key: const ValueKey('content'),
      children: [
        StatusFilterBar<ReservationStatus>(
          options: _options,
          selected: _filter,
          counts: counts,
          onSelected: (v) => setState(() => _filter = v),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.moduleFoodSaveDeep,
            child: AnimatedSwitcher(
              duration: FoodSaveMotion.fast,
              switchInCurve: FoodSaveMotion.curve,
              child: items.isEmpty
                  ? ListView(
                      key: ValueKey('empty-$_filter'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: AppSpacing.xxl),
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          color: AppColors.moduleFoodSave,
                          title: all.isEmpty
                              ? 'Aucune réservation pour le moment'
                              : 'Aucune réservation avec ce statut',
                          message: all.isEmpty
                              ? 'Les réservations de vos clients apparaîtront ici.'
                              : 'Choisissez un autre filtre.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      key: ValueKey('list-$_filter'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: AppSpacing.md,
                          endIndent: AppSpacing.md,
                          color: AppColors.outlineSoft),
                      itemBuilder: (context, i) => FadeSlideIn(
                        key: ValueKey('reservation-${items[i].id}'),
                        index: i,
                        child: MerchantReservationTile(
                          reservation: items[i],
                          showBasketTitle: widget.basketId == null,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReservationsSkeleton extends StatelessWidget {
  const _ReservationsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: 5,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              SkeletonBox(height: 44, width: 44, radius: AppRadius.pill),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 16, width: 160),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
