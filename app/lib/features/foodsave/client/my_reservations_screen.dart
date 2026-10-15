import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'booking/booking_format.dart';
import 'booking/reservation_card.dart';
import 'reservation_qr_screen.dart';

/// The client's FoodSave reservations: "En cours" (to pick up) and
/// "Historique" (picked up, expired, cancelled).
class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({
    super.key,
    required this.session,
    this.clock = systemClock,
  });

  final SessionController session;

  /// Injectable time source (tests).
  final BookingClock clock;

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late final ValueNotifier<DateTime> _now = ValueNotifier(widget.clock());
  late Future<List<ReservationDto>> _future;
  Timer? _ticker;
  List<ReservationDto> _items = const [];
  final Set<int> _expiredReloaded = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    // One shared ticker for every countdown on screen.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _now.dispose();
    super.dispose();
  }

  Future<List<ReservationDto>> _fetch() async {
    final items = await _api.myReservations();
    _items = items;
    return items;
  }

  Future<void> _reload() async {
    final future = _fetch();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Displayed by the FutureBuilder.
    }
  }

  void _tick() {
    final now = widget.clock();
    _now.value = now;
    // When an active QR runs out, reload once so the server's lazy expiry
    // moves it to the history tab.
    for (final r in _items) {
      final expiry = r.dateExpirationQr;
      if (isActiveReservation(r) &&
          expiry != null &&
          !now.isBefore(expiry) &&
          _expiredReloaded.add(r.id)) {
        _reload();
        return;
      }
    }
  }

  Future<void> _open(ReservationDto r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReservationQrScreen(
        session: widget.session,
        reservationId: r.id,
        clock: widget.clock,
      ),
    ));
    if (mounted) unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes réservations'),
          bottom: const TabBar(
            labelColor: AppColors.moduleFoodSaveDeep,
            unselectedLabelColor: AppColors.textSecondaryStrong,
            indicatorColor: AppColors.moduleFoodSave,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'En cours'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: FutureBuilder<List<ReservationDto>>(
          future: _future,
          builder: (context, snapshot) {
            final Widget child;
            if (!snapshot.hasData && !snapshot.hasError) {
              child = const BasketListSkeleton(key: ValueKey('loading'));
            } else if (snapshot.hasError && !snapshot.hasData) {
              child = FoodSaveErrorView(
                  key: const ValueKey('error'),
                  error: snapshot.error,
                  onRetry: _reload);
            } else {
              final all = snapshot.data!;
              final active = all.where(isActiveReservation).toList()
                ..sort((a, b) {
                  final ea = a.dateExpirationQr, eb = b.dateExpirationQr;
                  if (ea == null || eb == null) return 0;
                  return ea.compareTo(eb);
                });
              final history =
                  all.where((r) => !isActiveReservation(r)).toList();
              child = TabBarView(
                key: const ValueKey('content'),
                children: [
                  _list(context, active, activeTab: true),
                  _list(context, history, activeTab: false),
                ],
              );
            }
            return AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : FoodSaveMotion.medium,
              switchInCurve: FoodSaveMotion.curve,
              child: child,
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<ReservationDto> items,
      {required bool activeTab}) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.moduleFoodSaveDeep,
        onRefresh: _reload,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EmptyState(
                      icon: activeTab
                          ? Icons.qr_code_2
                          : Icons.history_rounded,
                      color: AppColors.moduleFoodSave,
                      title: activeTab
                          ? 'Aucune réservation en cours'
                          : 'Aucun historique pour le moment',
                      message: activeTab
                          ? 'Réservez un panier anti-gaspillage près de chez vous et retrouvez ici votre QR code de retrait.'
                          : 'Vos paniers retirés, expirés ou annulés apparaîtront ici.',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl),
                      child: FilledButton.icon(
                        style: foodSaveFilledStyle(),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Découvrir les paniers'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.moduleFoodSaveDeep,
      onRefresh: _reload,
      child: ListView.separated(
        key: PageStorageKey(activeTab ? 'active' : 'history'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final r = items[i];
          return FadeSlideIn(
            key: ValueKey(r.id),
            index: i,
            child: ReservationCard(
              api: _api,
              reservation: r,
              now: _now,
              onTap: () => _open(r),
            ),
          );
        },
      ),
    );
  }
}
