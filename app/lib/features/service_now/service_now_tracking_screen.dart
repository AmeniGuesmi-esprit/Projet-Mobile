import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/live/live_refresh.dart';
import '../../core/location/device_location_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../foodsave/client/basket_map_view.dart' show FoodSaveMapTiles;
import 'service_now_api.dart';
import 'service_now_format.dart';

/// Map of a trip. The client watches the prestataire; with [shareLocation]
/// the prestataire's phone also sends its position while the screen is open.
class ServiceNowTrackingScreen extends StatefulWidget {
  const ServiceNowTrackingScreen({
    super.key,
    required this.session,
    required this.interventionId,
    required this.shareLocation,
  });

  final SessionController session;
  final int interventionId;
  final bool shareLocation;

  @override
  State<ServiceNowTrackingScreen> createState() =>
      _ServiceNowTrackingScreenState();
}

class _ServiceNowTrackingScreenState extends State<ServiceNowTrackingScreen>
    with LiveRefresh<ServiceNowTrackingScreen> {
  static const Duration _shareInterval = Duration(seconds: 10);

  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);
  final MapController _map = MapController();
  Timer? _shareTimer;
  ServiceTrackingDto? _tracking;
  bool _mapReady = false;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    liveRefresh();
    if (widget.shareLocation) {
      _shareTimer = Timer.periodic(_shareInterval, (_) => _sharePosition());
      _sharePosition();
    }
  }

  @override
  void dispose() {
    _shareTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _sharePosition() async {
    try {
      final position = await const DeviceLocationService().currentPosition();
      await _api.updatePosition(
        widget.interventionId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // A missed update is harmless: the next one follows in 10 seconds.
    }
  }

  @override
  Future<void> liveRefresh() async {
    try {
      final tracking = await _api.tracking(widget.interventionId);
      if (!mounted) return;
      setState(() => _tracking = tracking);
      _fit();
    } catch (_) {
      // Keeps the last known position on screen.
    }
  }

  LatLng? get _current {
    final latitude = _tracking?.latitude;
    final longitude = _tracking?.longitude;
    return latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
  }

  LatLng? get _destination {
    final latitude = _tracking?.destinationLatitude;
    final longitude = _tracking?.destinationLongitude;
    return latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
  }

  /// Frames the whole trip once; afterwards the user controls the map.
  void _fit() {
    if (!_mapReady || _fitted) return;
    final points = [_current, _destination].whereType<LatLng>().toList();
    if (points.isEmpty) return;
    _fitted = true;
    if (points.length == 1) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(48, 64, 48, 200),
      maxZoom: 16,
    ));
  }

  String _summary(ServiceTrackingDto? tracking) {
    if (tracking == null) return 'Chargement du trajet...';
    if (!tracking.enRoute) return 'Aucun trajet en cours';
    final seconds = tracking.dureeSecondes;
    final metres = tracking.distanceMetres;
    if (seconds == null || metres == null) {
      return 'L\'adresse du client n\'est pas localisée sur la carte';
    }
    final prefix = tracking.approximatif ? 'Environ ' : 'Arrivée dans ';
    return '$prefix${formatDuration(seconds)} · '
        '${formatDistanceKm(metres / 1000)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracking = _tracking;
    final current = _current;
    final destination = _destination;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shareLocation ? 'Mon trajet' : 'Suivi du prestataire'),
      ),
      body: Stack(
        children: [
          Semantics(
            label: 'Carte du trajet du prestataire',
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: FoodSaveMapTiles.fallbackCenter,
                initialZoom: 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _mapReady = true;
                  _fit();
                },
              ),
              children: [
                FoodSaveMapTiles.tileLayer(),
                if (tracking != null && tracking.points.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [
                        for (final (latitude, longitude) in tracking.points)
                          LatLng(latitude, longitude),
                      ],
                      strokeWidth: 6,
                      color: AppColors.info,
                      borderStrokeWidth: 2,
                      borderColor: AppColors.surface,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (destination != null)
                    Marker(
                      point: destination,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                  if (current != null)
                    Marker(
                      point: current,
                      width: 44,
                      height: 44,
                      child: const CircleAvatar(
                        backgroundColor: AppColors.info,
                        foregroundColor: AppColors.surface,
                        child: Icon(Icons.directions_car),
                      ),
                    ),
                ]),
                FoodSaveMapTiles.attribution(),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SafeArea(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_summary(tracking),
                          style: theme.textTheme.titleMedium),
                      if (widget.shareLocation) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Gardez cet écran ouvert pour partager votre position.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
