import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_form_screen.dart';
import 'merchant_basket_detail_screen.dart';
import 'merchant_reservations_screen.dart';
import 'scan_screen.dart';
import 'widgets/merchant_basket_card.dart';
import 'widgets/status_filter_bar.dart';

/// The merchant's baskets, filterable by status, with a "Nouveau panier" FAB.
class MerchantBasketsScreen extends StatefulWidget {
  const MerchantBasketsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<MerchantBasketsScreen> createState() => _MerchantBasketsScreenState();
}

class _MerchantBasketsScreenState extends State<MerchantBasketsScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late Future<List<BasketDto>> _future = _api.listMyBaskets();
  BasketStatus? _filter;

  static const List<FilterOption<BasketStatus>> _options = [
    FilterOption(null, 'Tous'),
    FilterOption(BasketStatus.disponible, 'Disponibles'),
    FilterOption(BasketStatus.epuise, 'Épuisés'),
    FilterOption(BasketStatus.expire, 'Expirés'),
    FilterOption(BasketStatus.annule, 'Annulés'),
  ];

  Future<void> _refresh() {
    final future = _api.listMyBaskets();
    setState(() => _future = future);
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _openDetail(BasketDto basket) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantBasketDetailScreen(
          session: widget.session, basketId: basket.id),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<BasketDto>(
      MaterialPageRoute(
          builder: (_) => BasketFormScreen(session: widget.session)),
    );
    if (created != null && mounted) {
      setState(() => _filter = null);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes paniers'),
        actions: [
          IconButton(
            tooltip: 'Scanner un QR code',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ScanScreen(session: widget.session))),
          ),
          IconButton(
            tooltip: 'Toutes les réservations',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    MerchantReservationsScreen(session: widget.session))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.moduleFoodSaveDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau panier'),
        tooltip: 'Publier un nouveau panier',
      ),
      body: FutureBuilder<List<BasketDto>>(
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
            child = const BasketListSkeleton(key: ValueKey('loading'));
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

  Widget _content(List<BasketDto> all) {
    final counts = <BasketStatus?, int>{null: all.length};
    for (final b in all) {
      counts[b.statut] = (counts[b.statut] ?? 0) + 1;
    }
    final items = _filter == null
        ? all
        : all.where((b) => b.statut == _filter).toList();

    return Column(
      key: const ValueKey('content'),
      children: [
        StatusFilterBar<BasketStatus>(
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
                  ? _empty(all.isEmpty)
                  : ListView.builder(
                      key: ValueKey('list-$_filter'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                          AppSpacing.xs, AppSpacing.md, 96),
                      itemCount: items.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: FadeSlideIn(
                          key: ValueKey('basket-${items[i].id}'),
                          index: i,
                          child: MerchantBasketCard(
                            api: _api,
                            basket: items[i],
                            onTap: () => _openDetail(items[i]),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(bool noBasketAtAll) => ListView(
        key: ValueKey('empty-$_filter'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          EmptyState(
            icon: noBasketAtAll
                ? Icons.shopping_basket_outlined
                : Icons.filter_alt_off_outlined,
            color: AppColors.moduleFoodSave,
            title: noBasketAtAll
                ? 'Aucun panier publié'
                : 'Aucun panier avec ce statut',
            message: noBasketAtAll
                ? 'Publiez votre premier panier anti-gaspillage avec le bouton « Nouveau panier ».'
                : 'Choisissez un autre filtre pour voir vos paniers.',
          ),
        ],
      );
}
