import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/foodsave_api.dart';
import '../platform/location_service.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_map_view.dart';
import 'widgets/client_format.dart';

/// "7 min", "1 h 02" (rounded up to the minute).
String routeDurationFr(int seconds) {
  final minutes = (seconds / 60).ceil().clamp(1, 1 << 30);
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

/// "850 m", "5,3 km", "24 km".
String routeDistanceFr(int metres) {
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  final km = metres / 1000;
  return km < 10
      ? '${km.toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${km.round()} km';
}

/// Google Maps directions to [store] (Google uses the live position as the
/// start, so turn-by-turn navigation works even without our own fix).
Uri googleMapsDirectionsUri(StoreDto store, TravelMode mode) => Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'destination': '${store.latitude},${store.longitude}',
        'travelmode': switch (mode) {
          TravelMode.voiture => 'driving',
          TravelMode.pied => 'walking',
        },
      },
    );

/// Route from the client's position to a store, by car or on foot: drawn on
/// the map with duration / distance, and handed over to Google Maps for
/// turn-by-turn navigation.
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.api,
    required this.store,
    this.fromLatitude,
    this.fromLongitude,
    this.locate,
    this.launcher,
    this.clock = DateTime.now,
    this.tileLayer,
  });

  final FoodSaveApi api;
  final StoreDto store;

  /// Known start (e.g. the discovery map's position); otherwise the GPS.
  final double? fromLatitude;
  final double? fromLongitude;

  /// GPS read (tests). Defaults to [FoodSaveLocationService].
  final Future<LocationResult> Function()? locate;

  /// Opens an external URL (tests). Defaults to url_launcher.
  final Future<bool> Function(Uri uri)? launcher;
  final DateTime Function() clock;
  final Widget? tileLayer;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final MapController _map = MapController();
  bool _mapReady = false;

  TravelMode _mode = TravelMode.voiture;
  LatLng? _from;
  LocationIssue? _locationIssue;
  bool _locating = false;

  final Map<TravelMode, RouteDto> _routes = {};
  final Set<TravelMode> _loading = {};
  final Map<TravelMode, Object> _errors = {};

  LatLng get _to => LatLng(widget.store.latitude, widget.store.longitude);

  @override
  void initState() {
    super.initState();
    final lat = widget.fromLatitude;
    final lng = widget.fromLongitude;
    if (lat != null && lng != null && isValidLatLng(lat, lng)) {
      _from = LatLng(lat, lng);
      _load(_mode);
    } else {
      _locate();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationIssue = null;
    });
    LocationResult result;
    try {
      final last = FoodSaveLocationService.instance.last;
      result = widget.locate != null
          ? await widget.locate!()
          : (last != null && last.hasPosition)
              ? last
              : await FoodSaveLocationService.instance.currentPosition();
    } catch (_) {
      result = const LocationResult(issue: LocationIssue.unavailable);
    }
    if (!mounted) return;
    final lat = result.latitude;
    final lng = result.longitude;
    setState(() {
      _locating = false;
      if (result.hasPosition && lat != null && lng != null) {
        _from = LatLng(lat, lng);
      } else {
        _locationIssue = result.issue ?? LocationIssue.unavailable;
      }
    });
    if (_from != null) unawaited(_load(_mode));
  }

  Future<void> _load(TravelMode mode) async {
    final from = _from;
    if (from == null || _routes.containsKey(mode) || _loading.contains(mode)) {
      _fit();
      return;
    }
    setState(() {
      _loading.add(mode);
      _errors.remove(mode);
    });
    try {
      final route = await widget.api.routeTo(
        fromLatitude: from.latitude,
        fromLongitude: from.longitude,
        toLatitude: widget.store.latitude,
        toLongitude: widget.store.longitude,
        mode: mode,
      );
      if (!mounted) return;
      setState(() => _routes[mode] = route);
      if (mode == _mode) _fit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[mode] = e);
    } finally {
      if (mounted) setState(() => _loading.remove(mode));
    }
  }

  void _select(TravelMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _load(mode);
  }

  /// Frames the whole trip (route, or start + store) above the summary card.
  void _fit() {
    if (!_mapReady) return;
    final route = _routes[_mode];
    final points = route != null
        ? [for (final (lat, lng) in route.points) LatLng(lat, lng)]
        : [?_from, _to];
    if (points.length < 2) {
      _map.move(_to, 15);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(48, 96, 48, 300),
      maxZoom: 17,
    ));
  }

  Future<void> _openGoogleMaps() async {
    final uri = googleMapsDirectionsUri(widget.store, _mode);
    var opened = false;
    try {
      opened = await (widget.launcher ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (e) {
      developer.log('launchUrl failed: $e', name: 'foodsave');
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text(
                'Impossible d\'ouvrir Google Maps sur cet appareil.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _routes[_mode];
    final from = _from;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Itinéraire'),
            Text(widget.store.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryStrong)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Semantics(
            label: route == null
                ? 'Carte : ${widget.store.nom}'
                : 'Carte de l\'itinéraire ${_mode.label.toLowerCase()} '
                    'vers ${widget.store.nom}',
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _to,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _mapReady = true;
                  _fit();
                },
              ),
              children: [
                widget.tileLayer ?? FoodSaveMapTiles.tileLayer(),
                if (route != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [
                        for (final (lat, lng) in route.points) LatLng(lat, lng)
                      ],
                      strokeWidth: 6,
                      color: _mode == TravelMode.voiture
                          ? AppColors.info
                          : AppColors.moduleFoodSaveDeep,
                      borderStrokeWidth: 2,
                      borderColor: AppColors.surface,
                      pattern: _mode == TravelMode.pied
                          ? const StrokePattern.dotted(spacingFactor: 1.6)
                          : const StrokePattern.solid(),
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (from != null)
                    Marker(
                        point: from,
                        width: 36,
                        height: 36,
                        child: const _StartDot()),
                  Marker(
                    point: _to,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on,
                        size: 48, color: AppColors.moduleFoodSaveDeep),
                  ),
                ]),
                FoodSaveMapTiles.attribution(),
              ],
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Center(
              child: Material(
                color: AppColors.surface,
                elevation: 3,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SegmentedButton<TravelMode>(
                  key: const ValueKey('travel-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: TravelMode.voiture,
                        icon: Icon(Icons.directions_car_outlined),
                        label: Text('Voiture')),
                    ButtonSegment(
                        value: TravelMode.pied,
                        icon: Icon(Icons.directions_walk),
                        label: Text('À pied')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => _select(s.first),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SafeArea(
              top: false,
              child: _SummaryCard(
                store: widget.store,
                mode: _mode,
                route: route,
                locating: _locating,
                loading: _loading.contains(_mode),
                locationIssue: _locationIssue,
                error: _errors[_mode],
                arrival: route == null
                    ? null
                    // Same rounding as the displayed duration.
                    : widget.clock().add(Duration(
                        minutes: (route.dureeSecondes / 60).ceil())),
                onRetry: from == null ? _locate : () => _load(_mode),
                onOpenSettings: _locationIssue == null
                    ? null
                    : () => FoodSaveLocationService.instance
                        .openSettings(_locationIssue!),
                onGoogleMaps: _openGoogleMaps,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartDot extends StatelessWidget {
  const _StartDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Votre position',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.info.withValues(alpha: 0.2),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.store,
    required this.mode,
    required this.route,
    required this.locating,
    required this.loading,
    required this.locationIssue,
    required this.error,
    required this.arrival,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onGoogleMaps,
  });

  final StoreDto store;
  final TravelMode mode;
  final RouteDto? route;
  final bool locating;
  final bool loading;
  final LocationIssue? locationIssue;
  final Object? error;
  final DateTime? arrival;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;
  final VoidCallback onGoogleMaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final r = route;
    final Widget head;
    if (r != null) {
      head = Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(routeDurationFr(r.dureeSecondes),
                    key: const ValueKey('route-duration'),
                    style: theme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: mode == TravelMode.voiture
                            ? AppColors.info
                            : AppColors.moduleFoodSaveDeep)),
                const SizedBox(width: AppSpacing.xs),
                Text('· ${routeDistanceFr(r.distanceMetres)}',
                    style: theme.titleMedium),
              ],
            ),
            if (arrival != null)
              Text(
                  '${mode.label} · arrivée vers ${clockFr(arrival!)}',
                  style: theme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryStrong)),
          ],
        ),
      );
    } else if (locating || loading) {
      head = Row(
        children: [
          const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
                locating
                    ? 'Recherche de votre position…'
                    : 'Calcul de l\'itinéraire…',
                style: theme.bodyMedium),
          ),
        ],
      );
    } else {
      final issue = locationIssue;
      final message = issue != null
          ? FoodSaveLocationService.messageFor(issue)
          : error != null
              ? 'Itinéraire indisponible pour le moment. Vous pouvez '
                  'réessayer ou ouvrir Google Maps.'
              : 'Calcul de l\'itinéraire…';
      head = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(message, style: theme.bodyMedium)),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
              if (onOpenSettings != null &&
                  (issue == LocationIssue.permissionDeniedForever ||
                      issue == LocationIssue.serviceDisabled))
                TextButton(
                    onPressed: onOpenSettings, child: const Text('Réglages')),
            ],
          ),
        ],
      );
    }

    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: AppColors.text.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.storefront_outlined,
                    size: 20, color: AppColors.moduleFoodSaveDeep),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text('${store.nom} · ${store.adresse}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall
                          ?.copyWith(color: AppColors.textSecondaryStrong)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              key: const ValueKey('open-google-maps'),
              style: foodSaveFilledStyle(),
              onPressed: onGoogleMaps,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Démarrer dans Google Maps'),
            ),
          ],
        ),
      ),
    );
  }
}
