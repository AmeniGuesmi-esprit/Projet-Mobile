import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/foodsave_api.dart';
import '../platform/foodsave_notification_poller.dart';
import '../platform/foodsave_notifications_screen.dart';
import '../platform/location_service.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_detail_screen.dart';
import 'basket_map_view.dart';
import 'route_screen.dart';
import 'my_reservations_screen.dart';
import 'widgets/client_basket_card.dart';

/// Quick filters of the client list (first one = every offer).
enum DiscoveryFilter {
  tout,
  proche,
  grosseReduction;

  /// "≤ 3 km" filter radius.
  static const double nearbyKm = 3;

  /// "-50 % et +" filter threshold.
  static const int bigDiscountPercent = 50;

  String get label => switch (this) {
        DiscoveryFilter.tout => 'Tout',
        DiscoveryFilter.proche => '≤ ${nearbyKm.round()} km',
        DiscoveryFilter.grosseReduction => '-$bigDiscountPercent % et +',
      };

  /// Small heading shown above [label] in the filter button.
  String? get title => switch (this) {
        DiscoveryFilter.tout => null,
        DiscoveryFilter.proche => 'Distance',
        DiscoveryFilter.grosseReduction => 'Réduction',
      };

  String get tooltip => switch (this) {
        DiscoveryFilter.tout => 'Toutes les offres',
        DiscoveryFilter.proche =>
          'Offres à ${nearbyKm.round()} km ou moins',
        DiscoveryFilter.grosseReduction =>
          'Réduction de $bigDiscountPercent % ou plus',
      };
}

/// Client home of FoodSave: nearby anti-waste baskets with search,
/// category / sort filters and a list ⇄ map toggle.
class ClientDiscoveryScreen extends StatefulWidget {
  const ClientDiscoveryScreen({super.key, required this.session});

  final SessionController session;

  /// Search debounce (typing → request).
  static const Duration searchDebounce = Duration(milliseconds: 350);

  @override
  State<ClientDiscoveryScreen> createState() => _ClientDiscoveryScreenState();
}

class _ClientDiscoveryScreenState extends State<ClientDiscoveryScreen>
    with WidgetsBindingObserver {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  final FoodSaveLocationService _location = FoodSaveLocationService.instance;
  final TextEditingController _search = TextEditingController();

  FoodCategory? _category;
  DiscoveryFilter _filter = DiscoveryFilter.tout;
  String _query = '';
  bool _showMap = false;
  Timer? _debounce;

  /// Position used by the last request (null = server-side / none).
  ({double latitude, double longitude})? _loadedWith;

  late Future<List<BasketDto>> _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
    unawaited(_syncLocation(askPermission: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system settings: try again silently.
    if (state == AppLifecycleState.resumed && _location.last?.issue != null) {
      unawaited(_syncLocation(askPermission: false));
    }
  }

  ({double latitude, double longitude})? get _position {
    final last = _location.last;
    if (last == null || !last.hasPosition) return null;
    return (latitude: last.latitude!, longitude: last.longitude!);
  }

  Future<List<BasketDto>> _load() {
    final pos = _position;
    _loadedWith = pos;
    // "≤ 3 km" needs a position: without one nothing can be close.
    if (_filter == DiscoveryFilter.proche && pos == null) {
      return Future.value(const <BasketDto>[]);
    }
    return _api.listBaskets(
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      rayonKm: _filter == DiscoveryFilter.proche
          ? DiscoveryFilter.nearbyKm
          : null,
      reductionMin: _filter == DiscoveryFilter.grosseReduction
          ? DiscoveryFilter.bigDiscountPercent
          : null,
      categorie: _category,
      recherche: _query,
      // Biggest discounts first for the discount filter, else nearest.
      tri: _filter == DiscoveryFilter.grosseReduction
          ? BasketSort.reduction
          : BasketSort.distance,
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  /// Reads the GPS (and syncs it to the server); reloads when a new
  /// position is available.
  Future<void> _syncLocation({required bool askPermission}) async {
    final result =
        await _location.refresh(_api, askPermission: askPermission);
    if (!mounted || !result.hasPosition) return;
    final used = _loadedWith;
    if (used == null ||
        haversineKm(used.latitude, used.longitude, result.latitude!,
                result.longitude!) >
            0.05) {
      _reload();
    }
  }

  Future<void> _pullToRefresh() async {
    await _location.refresh(_api, askPermission: false);
    final future = _load();
    if (mounted) {
      setState(() {
        _future = future;
      });
    }
    try {
      await future;
    } catch (_) {
      // Rendered by the FutureBuilder.
    }
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    setState(() {}); // clear button visibility
    _debounce = Timer(ClientDiscoveryScreen.searchDebounce, () {
      if (text.trim() == _query) return;
      _query = text.trim();
      _reload();
    });
  }

  void _submitSearch(String text) {
    _debounce?.cancel();
    if (text.trim() == _query) return;
    _query = text.trim();
    _reload();
  }

  void _clearSearch() {
    _search.clear();
    _submitSearch('');
    setState(() {});
  }

  void _selectCategory(FoodCategory? c) {
    if (c == _category) return;
    _category = c;
    _reload();
  }

  void _selectFilter(DiscoveryFilter f) {
    if (f == _filter) return;
    _filter = f;
    _reload();
  }

  Future<void> _openBasket(BasketDto b) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BasketDetailScreen(
          session: widget.session, basketId: b.id, initialBasket: b),
    ));
    // Quantities may have changed (own reservation, other clients).
    _reload();
  }

  void _openReservations() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MyReservationsScreen(session: widget.session)));

  void _openNotifications() => Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) =>
              FoodSaveNotificationsScreen(session: widget.session)));

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Paniers anti-gaspi',
            style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          IconButton(
            tooltip: 'Mes réservations',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: _openReservations,
          ),
          ValueListenableBuilder<int>(
            valueListenable: FoodSaveNotificationPoller.instance.unread,
            builder: (context, unread, _) => IconButton(
              tooltip: unread > 0
                  ? 'Notifications ($unread non lue${unread > 1 ? 's' : ''})'
                  : 'Notifications',
              onPressed: _openNotifications,
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: FutureBuilder<List<BasketDto>>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final items = snapshot.hasError ? null : snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Subtitle(
                count: items?.length,
                nearby: _loadedWith != null ||
                    (items?.any((b) => b.distanceKm != null) ?? false),
              ),
              ListenableBuilder(
                listenable: _location,
                builder: (context, _) => _LocationBanner(
                  issue: _location.last?.issue,
                  onEnable: () => _syncLocation(askPermission: true),
                  onOpenSettings: (issue) => _location.openSettings(issue),
                ),
              ),
              _SearchField(
                controller: _search,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                onClear: _clearSearch,
              ),
              _CategoryChips(selected: _category, onSelected: _selectCategory),
              _FilterRow(
                filter: _filter,
                showMap: _showMap,
                onFilter: _selectFilter,
                onToggleView: () => setState(() => _showMap = !_showMap),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _content(snapshot, items)),
                    if (loading && items != null)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: AppColors.moduleFoodSaveDeep,
                          backgroundColor: AppColors.moduleFoodSaveSoft,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _content(
      AsyncSnapshot<List<BasketDto>> snapshot, List<BasketDto>? items) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget child;
    if (snapshot.hasError &&
        snapshot.connectionState != ConnectionState.waiting) {
      child = _ScrollableFill(
        key: const ValueKey('error'),
        onRefresh: _pullToRefresh,
        child: FoodSaveErrorView(error: snapshot.error, onRetry: _reload),
      );
    } else if (items == null) {
      child = const BasketListSkeleton(key: ValueKey('skeleton'));
    } else if (_showMap) {
      final pos = _position;
      child = BasketMapView(
        key: const ValueKey('map'),
        api: _api,
        baskets: items,
        userLatitude: pos?.latitude,
        userLongitude: pos?.longitude,
        onOpenBasket: _openBasket,
        onDirections: (store) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RouteScreen(
              api: _api,
              store: store,
              fromLatitude: pos?.latitude,
              fromLongitude: pos?.longitude,
            ),
          ),
        ),
      );
    } else if (items.isEmpty) {
      child = _ScrollableFill(
        key: const ValueKey('empty'),
        onRefresh: _pullToRefresh,
        child: EmptyState(
          icon: Icons.shopping_basket_outlined,
          color: AppColors.moduleFoodSave,
          title: switch (_filter) {
            DiscoveryFilter.tout =>
              'Aucun panier près de chez vous pour le moment',
            DiscoveryFilter.proche =>
              'Aucun panier à ${DiscoveryFilter.nearbyKm.round()} km ou moins',
            DiscoveryFilter.grosseReduction =>
              'Aucun panier à -${DiscoveryFilter.bigDiscountPercent} % ou plus',
          },
          message: _filter == DiscoveryFilter.proche && _position == null
              ? 'Activez la localisation pour voir les paniers proches de vous.'
              : _query.isNotEmpty || _category != null
                  ? 'Essayez une autre recherche ou une autre catégorie.'
                  : _filter != DiscoveryFilter.tout
                      ? 'Touchez « Tout » pour voir toutes les offres.'
                      : 'Revenez plus tard : les commerçants publient leurs invendus en fin de journée.',
        ),
      );
    } else {
      child = RefreshIndicator(
        key: const ValueKey('list'),
        color: AppColors.moduleFoodSaveDeep,
        onRefresh: _pullToRefresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final b = items[i];
            return FadeSlideIn(
              key: ValueKey('basket-${b.id}'),
              index: i,
              child: ClientBasketCard(
                api: _api,
                basket: b,
                onTap: () => _openBasket(b),
              ),
            );
          },
        ),
      );
    }
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      switchInCurve: FoodSaveMotion.curve,
      switchOutCurve: FoodSaveMotion.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------- header

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.count, required this.nearby});

  /// Null while the first load is running.
  final int? count;
  final bool nearby;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final where = nearby ? 'près de chez vous' : 'disponibles';
    final text = n == null
        ? 'Recherche des paniers près de chez vous…'
        : n == 0
            ? 'Aucun résultat pour le moment'
            : n == 1
                ? '1 panier ${nearby ? where : 'disponible'}'
                : '$n paniers $where';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
      child: Semantics(
        liveRegion: true,
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondaryStrong)),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({
    required this.issue,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final LocationIssue? issue;
  final VoidCallback onEnable;
  final ValueChanged<LocationIssue> onOpenSettings;

  static String messageFor(LocationIssue issue) => switch (issue) {
        LocationIssue.permissionDenied =>
          'Activez la localisation pour voir la distance et recevoir les paniers à moins de 5 km',
        _ => FoodSaveLocationService.messageFor(issue),
      };

  @override
  Widget build(BuildContext context) {
    final i = issue;
    final Widget child;
    if (i == null) {
      child = const SizedBox(width: double.infinity);
    } else {
      final settings = i == LocationIssue.permissionDeniedForever ||
          i == LocationIssue.serviceDisabled;
      child = Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.xxs),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_off_outlined, color: AppColors.info),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(messageFor(i),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: settings ? () => onOpenSettings(i) : onEnable,
                  child: Text(switch (i) {
                    LocationIssue.permissionDenied => 'Activer la localisation',
                    LocationIssue.unavailable => 'Réessayer',
                    _ => 'Ouvrir les paramètres',
                  }),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AnimatedSize(
      duration: FoodSaveMotion.medium,
      curve: FoodSaveMotion.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Rechercher un panier, un commerce…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer la recherche',
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  ),
          ),
        ),
      );
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final FoodCategory? selected;
  final ValueChanged<FoodCategory?> onSelected;

  Widget _chip(String label, IconData icon, bool isSelected,
          VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        avatar: Icon(icon,
            size: 18,
            color: isSelected
                ? AppColors.moduleFoodSaveDeep
                : AppColors.textSecondaryStrong),
        selected: isSelected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.moduleFoodSaveSoft,
        backgroundColor: AppColors.surface,
        labelStyle: TextStyle(
          color: AppColors.text,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
            color: isSelected ? AppColors.moduleFoodSave : AppColors.outline),
        shape: const StadiumBorder(),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
          children: [
            _chip('Toutes', Icons.apps, selected == null,
                () => onSelected(null)),
            for (final c in FoodCategory.values) ...[
              const SizedBox(width: AppSpacing.xs),
              _chip(c.label, FoodCategoryMeta.icon(c), selected == c,
                  () => onSelected(c)),
            ],
          ],
        ),
      );
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.showMap,
    required this.onFilter,
    required this.onToggleView,
  });

  final DiscoveryFilter filter;
  final bool showMap;
  final ValueChanged<DiscoveryFilter> onFilter;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.xs, AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: SegmentedButton<DiscoveryFilter>(
                segments: [
                  for (final f in DiscoveryFilter.values)
                    ButtonSegment(
                      value: f,
                      // Name over value ("Distance" / "≤ 3 km"); shrinks
                      // rather than truncating on narrow phones.
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (f.title != null)
                              Text(f.title!,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                            Text(f.label,
                                maxLines: 1,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      tooltip: f.tooltip,
                    ),
                ],
                selected: {filter},
                showSelectedIcon: false,
                onSelectionChanged: (set) => onFilter(set.first),
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  selectedBackgroundColor: AppColors.moduleFoodSaveSoft,
                  selectedForegroundColor: AppColors.moduleFoodSaveDeep,
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.outline),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: showMap ? 'Afficher la liste' : 'Afficher la carte',
              onPressed: onToggleView,
              icon: AnimatedSwitcher(
                duration: FoodSaveMotion.fast,
                child: Icon(
                  showMap ? Icons.view_list_outlined : Icons.map_outlined,
                  key: ValueKey(showMap),
                  color: AppColors.moduleFoodSaveDeep,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Centres [child] while keeping pull-to-refresh available.
class _ScrollableFill extends StatelessWidget {
  const _ScrollableFill({super.key, required this.child, required this.onRefresh});

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: AppColors.moduleFoodSaveDeep,
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: child),
            ),
          ),
        ),
      );
}
