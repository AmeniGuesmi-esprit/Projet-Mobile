import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'widgets/client_basket_card.dart';
import 'widgets/client_format.dart';

/// OpenStreetMap tiles + attribution, shared by every FoodSave map.
///
/// Tests set [debugTileLayer] so no tile (nor the tile cache, which needs
/// `path_provider`) is ever touched.
class FoodSaveMapTiles {
  const FoodSaveMapTiles._();

  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.proxilife.app';

  /// Replaces the network tile layer (tests).
  @visibleForTesting
  static Widget Function()? debugTileLayer;

  /// Default centre when nothing is known: Tunis.
  static const LatLng fallbackCenter = LatLng(36.8065, 10.1815);

  static Widget tileLayer() =>
      debugTileLayer?.call() ??
      TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: userAgentPackageName,
        maxNativeZoom: 19,
      );

  static Widget attribution() => const RichAttributionWidget(
        showFlutterMapAttribution: false,
        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
      );
}

/// Baskets of one store, cheapest first.
class _StoreGroup {
  _StoreGroup(this.store, this.baskets);

  final StoreDto store;
  final List<BasketDto> baskets;

  int get minPrice => baskets.first.prixCentimes;
  double? get distanceKm => baskets.first.distanceKm;
  LatLng get point => LatLng(store.latitude, store.longitude);
}

/// Interactive map of the listed baskets: one price pill per store, the
/// user's position with the 5 km notification radius, tap → preview card.
class BasketMapView extends StatefulWidget {
  const BasketMapView({
    super.key,
    required this.api,
    required this.baskets,
    required this.onOpenBasket,
    this.userLatitude,
    this.userLongitude,
    this.tileLayer,
  });

  final FoodSaveApi api;
  final List<BasketDto> baskets;
  final ValueChanged<BasketDto> onOpenBasket;
  final double? userLatitude;
  final double? userLongitude;

  /// Overrides [FoodSaveMapTiles.tileLayer] (tests / offline).
  final Widget? tileLayer;

  @override
  State<BasketMapView> createState() => _BasketMapViewState();
}

class _BasketMapViewState extends State<BasketMapView> {
  final MapController _controller = MapController();
  late List<_StoreGroup> _groups = _group(widget.baskets);
  int? _selectedStoreId;

  LatLng? get _user =>
      widget.userLatitude != null && widget.userLongitude != null
          ? LatLng(widget.userLatitude!, widget.userLongitude!)
          : null;

  static List<_StoreGroup> _group(List<BasketDto> baskets) {
    final byStore = <int, _StoreGroup>{};
    for (final b in baskets) {
      final s = b.commerce;
      if (s == null || !isValidLatLng(s.latitude, s.longitude)) continue;
      byStore.putIfAbsent(s.id, () => _StoreGroup(s, [])).baskets.add(b);
    }
    for (final g in byStore.values) {
      g.baskets.sort((a, b) => a.prixCentimes.compareTo(b.prixCentimes));
    }
    return byStore.values.toList();
  }

  @override
  void didUpdateWidget(BasketMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.baskets, widget.baskets)) {
      _groups = _group(widget.baskets);
      if (!_groups.any((g) => g.store.id == _selectedStoreId)) {
        _selectedStoreId = null;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MapOptions _options() {
    final user = _user;
    const flags = InteractiveFlag.all & ~InteractiveFlag.rotate;
    void onTap(TapPosition _, LatLng _) {
      if (_selectedStoreId != null) setState(() => _selectedStoreId = null);
    }

    if (user != null) {
      return MapOptions(
        initialCenter: user,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(flags: flags),
        onTap: onTap,
      );
    }
    if (_groups.length > 1) {
      return MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: [for (final g in _groups) g.point],
          padding: const EdgeInsets.all(AppSpacing.xxl * 2),
          maxZoom: 15,
        ),
        interactionOptions: const InteractionOptions(flags: flags),
        onTap: onTap,
      );
    }
    return MapOptions(
      initialCenter:
          _groups.isEmpty ? FoodSaveMapTiles.fallbackCenter : _groups.first.point,
      initialZoom: _groups.isEmpty ? 12 : 14,
      interactionOptions: const InteractionOptions(flags: flags),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    _StoreGroup? selected;
    for (final g in _groups) {
      if (g.store.id == _selectedStoreId) selected = g;
    }
    return Stack(
      children: [
        Semantics(
          label: 'Carte des paniers : ${_groups.length} commerce'
              '${_groups.length > 1 ? 's' : ''}',
          child: FlutterMap(
            mapController: _controller,
            options: _options(),
            children: [
              widget.tileLayer ?? FoodSaveMapTiles.tileLayer(),
              if (user != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: user,
                    radius: foodSaveNotificationRadiusKm * 1000,
                    useRadiusInMeter: true,
                    color: AppColors.moduleFoodSave.withValues(alpha: 0.08),
                    borderColor:
                        AppColors.moduleFoodSave.withValues(alpha: 0.45),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              MarkerLayer(
                markers: [
                  for (final g in _groups)
                    Marker(
                      point: g.point,
                      width: 120,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: _PriceMarker(
                        key: ValueKey('store-marker-${g.store.id}'),
                        group: g,
                        selected: g.store.id == _selectedStoreId,
                        onTap: () =>
                            setState(() => _selectedStoreId = g.store.id),
                      ),
                    ),
                  if (user != null)
                    Marker(
                      point: user,
                      width: 40,
                      height: 40,
                      child: const _UserDot(),
                    ),
                ],
              ),
              FoodSaveMapTiles.attribution(),
            ],
          ),
        ),
        if (user != null)
          Positioned(
            right: AppSpacing.md,
            top: AppSpacing.md,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(
                  side: BorderSide(color: AppColors.outlineSoft)),
              elevation: 2,
              child: IconButton(
                tooltip: 'Recentrer sur ma position',
                icon: const Icon(Icons.my_location, color: AppColors.info),
                onPressed: () => _controller.move(user, 13),
              ),
            ),
          ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.xxl,
          child: AnimatedSwitcher(
            duration: FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            switchOutCurve: FoodSaveMotion.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                        begin: const Offset(0, 0.15), end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            ),
            child: selected == null
                ? const SizedBox.shrink(key: ValueKey('no-preview'))
                : _StorePreview(
                    key: ValueKey('preview-${selected.store.id}'),
                    group: selected,
                    onOpen: widget.onOpenBasket,
                    onClose: () => setState(() => _selectedStoreId = null),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Price pill marker: FoodSave fill with dark text (4.9:1); deep fill with
/// white text when selected (5.6:1).
class _PriceMarker extends StatelessWidget {
  const _PriceMarker({
    super.key,
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final _StoreGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = group.baskets.length;
    final price = MoneyText.format(group.minPrice);
    final fg = selected ? Colors.white : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '${group.store.nom} : $count panier${count > 1 ? 's' : ''}, '
          'à partir de $price',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedContainer(
              duration: FoodSaveMotion.fast,
              curve: FoodSaveMotion.curve,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs - 2),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.moduleFoodSaveDeep
                    : AppColors.moduleFoodSave,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.text.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(price,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
                  if (count > 1) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Text('· $count',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's position: info-blue dot with a soft halo.
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Votre position',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.info.withValues(alpha: 0.20),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.info,
              border: Border.all(color: AppColors.surface, width: 3),
            ),
          ),
        ),
      );
}

/// Bottom preview of a store's baskets; tapping a row opens the detail.
class _StorePreview extends StatelessWidget {
  const _StorePreview({
    super.key,
    required this.group,
    required this.onOpen,
    required this.onClose,
  });

  final _StoreGroup group;
  final ValueChanged<BasketDto> onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final shown = group.baskets.take(3).toList();
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: AppColors.text.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined,
                    color: AppColors.moduleFoodSaveDeep),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(group.store.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium),
                ),
                DistancePill(group.distanceKm),
                IconButton(
                  tooltip: 'Fermer l\'aperçu',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            for (final b in shown)
              _PreviewRow(basket: b, onTap: () => onOpen(b)),
            if (group.baskets.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(
                    top: AppSpacing.xxs, right: AppSpacing.sm),
                child: Text(
                  '+ ${group.baskets.length - shown.length} autre(s) panier(s) '
                  'dans ce commerce',
                  style: theme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryStrong),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.basket, required this.onTap});

  final BasketDto basket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${basket.titre}, ${MoneyText.format(basket.prixCentimes)}, '
          '${pickupWindowFr(basket.creneauRetraitDebut, basket.creneauRetraitFin)}. '
          'Voir le détail',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.moduleFoodSaveSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(FoodCategoryMeta.icon(basket.categorie),
                      size: 20, color: AppColors.moduleFoodSaveDeep),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(basket.titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        pickupWindowFr(
                            basket.creneauRetraitDebut, basket.creneauRetraitFin),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall
                            ?.copyWith(color: AppColors.textSecondaryStrong),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                BasketPriceBlock(
                  prixCentimes: basket.prixCentimes,
                  prixInitialCentimes: basket.prixInitialCentimes,
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondaryStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small, non-interactive map centred on a store (basket detail).
class StoreMiniMap extends StatelessWidget {
  const StoreMiniMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.semanticLabel,
    this.height = 140,
    this.tileLayer,
  });

  final double latitude;
  final double longitude;
  final String semanticLabel;
  final double height;
  final Widget? tileLayer;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: height,
          child: IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                tileLayer ?? FoodSaveMapTiles.tileLayer(),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on,
                        size: 40, color: AppColors.moduleFoodSaveDeep),
                  ),
                ]),
                const _InlineAttribution(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Always-visible "© OpenStreetMap contributors" (OSM tile policy) for maps
/// the user cannot interact with; ellipsised instead of overflowing.
class _InlineAttribution extends StatelessWidget {
  const _InlineAttribution();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs, vertical: 2),
          color: AppColors.surface.withValues(alpha: 0.85),
          child: const Text(
            '© OpenStreetMap contributors',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.text),
          ),
        ),
      );
}
