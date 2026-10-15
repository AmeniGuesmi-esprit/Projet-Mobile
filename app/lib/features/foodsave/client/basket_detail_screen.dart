import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_map_view.dart';
import 'reservation_qr_screen.dart';
import 'reserve_flow.dart';
import 'widgets/client_basket_card.dart';
import 'widgets/client_format.dart';

/// Client view of one basket with its REAL server status, store and a
/// sticky "Réserver" call to action.
class BasketDetailScreen extends StatefulWidget {
  const BasketDetailScreen({
    super.key,
    required this.session,
    required this.basketId,
    this.initialBasket,
  });

  final SessionController session;
  final int basketId;

  /// Optional list copy shown (with the Hero image) while the fresh basket
  /// loads. The CTA stays disabled until the server answered.
  final BasketDto? initialBasket;

  @override
  State<BasketDetailScreen> createState() => _BasketDetailScreenState();
}

class _BasketDetailScreenState extends State<BasketDetailScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late Future<BasketDto> _future = _fetch();

  /// Last basket confirmed by the server (kept while reloading).
  BasketDto? _fresh;
  bool _reserving = false;

  Future<BasketDto> _fetch() async {
    final basket = await _api.getBasket(widget.basketId);
    _fresh = basket;
    return basket;
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _refresh() async {
    final future = _fetch();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Rendered by the FutureBuilder.
    }
  }

  Future<void> _reserve(BasketDto basket) async {
    if (_reserving) return;
    setState(() => _reserving = true);
    ReservationDto? reservation;
    try {
      reservation = await showReserveFlow(context,
          session: widget.session, basket: basket);
    } catch (e) {
      if (mounted) showFoodSaveError(context, e);
    } finally {
      if (mounted) setState(() => _reserving = false);
    }
    if (!mounted) return;
    _reload(); // the real remaining quantity changed
    if (reservation != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReservationQrScreen(
            session: widget.session, reservationId: reservation!.id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BasketDto>(
      future: _future,
      builder: (context, snapshot) {
        final verified = _fresh;
        final basket = verified ?? widget.initialBasket;
        final failed = snapshot.hasError &&
            snapshot.connectionState == ConnectionState.done;

        if (basket == null || (failed && verified == null)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Panier')),
            body: AnimatedSwitcher(
              duration: FoodSaveMotion.medium,
              child: failed
                  ? FoodSaveErrorView(
                      key: const ValueKey('error'),
                      error: snapshot.error,
                      onRetry: _reload)
                  : const _DetailSkeleton(key: ValueKey('loading')),
            ),
          );
        }

        return Scaffold(
          body: RefreshIndicator(
            color: AppColors.moduleFoodSaveDeep,
            onRefresh: _refresh,
            edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
            child: _DetailBody(api: _api, basket: basket),
          ),
          bottomNavigationBar: _ReserveBar(
            basket: basket,
            checking: verified == null,
            reason: verified == null
                ? null
                : unavailableReason(verified,
                    viewerId: widget.session.user?.id),
            busy: _reserving,
            onReserve: () => _reserve(basket),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ body

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.api, required this.basket});

  final FoodSaveApi api;
  final BasketDto basket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final topInset = MediaQuery.paddingOf(context).top;
    const imageHeight = 260.0;
    final savings = basket.prixInitialCentimes - basket.prixCentimes;
    final store = basket.commerce;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: imageHeight,
          backgroundColor: AppColors.surface,
          surfaceTintColor: AppColors.surface,
          leading: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Material(
              color: AppColors.surface.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: const BackButton(color: AppColors.text),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Hero(
              tag: basketHeroTag(basket.id),
              child: BasketImage(
                api: api,
                basket: basket,
                height: imageHeight + topInset,
                borderRadius: 0,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
          sliver: SliverList.list(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(basket.titre, style: theme.headlineMedium),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  DiscountBadge(
                    prixCentimes: basket.prixCentimes,
                    prixInitialCentimes: basket.prixInitialCentimes,
                    large: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _StatusOrStock(basket: basket),
                  DistancePill(basket.distanceKm),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.moduleFoodSaveSoft,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: BasketPriceBlock(
                        prixCentimes: basket.prixCentimes,
                        prixInitialCentimes: basket.prixInitialCentimes,
                        large: true,
                        alignEnd: false,
                      ),
                    ),
                    if (savings > 0)
                      Flexible(
                        child: Text(
                          'Vous économisez\n${MoneyText.format(savings)}',
                          textAlign: TextAlign.end,
                          style: theme.bodyMedium?.copyWith(
                              color: AppColors.text,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Contenu du panier', style: theme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(basket.contenu, style: theme.bodyLarge),
              const SizedBox(height: AppSpacing.xl),
              _InfoRow(
                icon: Icons.schedule,
                title: 'Créneau de retrait',
                value: pickupWindowFr(
                    basket.creneauRetraitDebut, basket.creneauRetraitFin),
              ),
              _InfoRow(
                icon: Icons.event_busy_outlined,
                title: 'À consommer avant',
                value: dateTimeFr(basket.dateExpiration),
              ),
              _InfoRow(
                icon: FoodCategoryMeta.icon(basket.categorie),
                title: 'Catégorie',
                value: basket.categorie.label,
              ),
              if (store != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Commerce', style: theme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                _StoreCard(store: store, distanceKm: basket.distanceKm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Real status chip when the basket is not on sale, else the stock hint.
class _StatusOrStock extends StatelessWidget {
  const _StatusOrStock({required this.basket});

  final BasketDto basket;

  @override
  Widget build(BuildContext context) {
    if (basket.statut != BasketStatus.disponible) {
      return BasketStatusChip(basket.statut);
    }
    if (basket.quantite <= 0) {
      return const BasketStatusChip(BasketStatus.epuise);
    }
    final label = remainingFr(basket.quantite);
    if (basket.quantite <= 2) {
      return Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LowStockChip(basket.quantite),
            const SizedBox(width: AppSpacing.xs),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.moduleFoodSaveSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: AppColors.moduleFoodSaveDeep),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.bodySmall
                          ?.copyWith(color: AppColors.textSecondaryStrong)),
                  Text(value,
                      style: theme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.distanceKm});

  final StoreDto store;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_outlined,
                  color: AppColors.moduleFoodSaveDeep),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.nom, style: theme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(store.adresse,
                        style: theme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondaryStrong)),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FoodCategoryMeta.icon(store.categorie),
                                size: 16, color: AppColors.textSecondaryStrong),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(store.categorie.label,
                                style: theme.bodySmall?.copyWith(
                                    color: AppColors.textSecondaryStrong)),
                          ],
                        ),
                        DistancePill(distanceKm),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isValidLatLng(store.latitude, store.longitude)) ...[
            const SizedBox(height: AppSpacing.md),
            StoreMiniMap(
              latitude: store.latitude,
              longitude: store.longitude,
              semanticLabel: 'Plan : ${store.nom}, ${store.adresse}',
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ bottom CTA

class _ReserveBar extends StatelessWidget {
  const _ReserveBar({
    required this.basket,
    required this.checking,
    required this.reason,
    required this.busy,
    required this.onReserve,
  });

  final BasketDto basket;
  final bool checking;
  final String? reason;
  final bool busy;
  final VoidCallback onReserve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final Widget child;
    if (checking) {
      child = FilledButton.icon(
        key: const ValueKey('checking'),
        style: foodSaveFilledStyle(),
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('Vérification de la disponibilité…'),
      );
    } else if (reason != null) {
      final status = basket.statut == BasketStatus.disponible &&
              basket.quantite <= 0
          ? BasketStatus.epuise
          : basket.statut;
      child = Column(
        key: ValueKey('unavailable-${status.apiValue}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (status != BasketStatus.disponible) ...[
                BasketStatusChip(status),
                const SizedBox(width: AppSpacing.sm),
              ] else ...[
                const Icon(Icons.schedule, color: AppColors.textSecondaryStrong),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(reason!,
                      style: theme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondaryStrong)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            style: foodSaveFilledStyle(),
            onPressed: null,
            child: const Text('Réservation indisponible'),
          ),
        ],
      );
    } else {
      child = Row(
        key: const ValueKey('available'),
        children: [
          BasketPriceBlock(
            prixCentimes: basket.prixCentimes,
            prixInitialCentimes: basket.prixInitialCentimes,
            alignEnd: false,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              style: foodSaveFilledStyle(),
              onPressed: busy ? null : onReserve,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.shopping_bag_outlined),
              label: const Text('Réserver'),
            ),
          ),
        ],
      );
    }
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: AppColors.text.withValues(alpha: 0.25),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: AnimatedSize(
            duration: FoodSaveMotion.medium,
            curve: FoodSaveMotion.curve,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: FoodSaveMotion.medium,
              switchInCurve: FoodSaveMotion.curve,
              switchOutCurve: FoodSaveMotion.curve,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- loading

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 220, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 28, width: 240),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 18, width: 140),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 72, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 16),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 16, width: 260),
        ],
      );
}
