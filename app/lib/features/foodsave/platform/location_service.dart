import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../data/foodsave_api.dart';

/// Why no position is available.
enum LocationIssue { permissionDenied, permissionDeniedForever, serviceDisabled, unavailable }

/// Last GPS fix (UTC) or the reason there is none.
class LocationResult {
  const LocationResult({this.latitude, this.longitude, this.issue});

  final double? latitude;
  final double? longitude;
  final LocationIssue? issue;

  bool get hasPosition => latitude != null && longitude != null;
}

/// Location permission as seen by [GeoBackend].
enum GeoPermission { granted, denied, deniedForever }

/// Thin seam over the platform GPS so tests never touch platform channels.
abstract class GeoBackend {
  const GeoBackend();

  Future<bool> isServiceEnabled();
  Future<GeoPermission> checkPermission();
  Future<GeoPermission> requestPermission();

  /// Fresh fix, or throws / returns null when none can be obtained.
  Future<({double latitude, double longitude})?> currentPosition();

  /// Cached fix from the OS, if any.
  Future<({double latitude, double longitude})?> lastKnownPosition();

  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

/// Real implementation backed by `geolocator`.
class GeolocatorBackend extends GeoBackend {
  const GeolocatorBackend();

  static GeoPermission _map(LocationPermission p) => switch (p) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          GeoPermission.granted,
        LocationPermission.deniedForever => GeoPermission.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine =>
          GeoPermission.denied,
      };

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<GeoPermission> checkPermission() async =>
      _map(await Geolocator.checkPermission());

  @override
  Future<GeoPermission> requestPermission() async =>
      _map(await Geolocator.requestPermission());

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: p.latitude, longitude: p.longitude);
  }

  @override
  Future<({double latitude, double longitude})?> lastKnownPosition() async {
    final p = await Geolocator.getLastKnownPosition();
    return p == null ? null : (latitude: p.latitude, longitude: p.longitude);
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

/// GPS access + sync of the client's position to the server.
///
/// Listenable: notifies when [last] changes (e.g. to refresh a distance UI).
class FoodSaveLocationService extends ChangeNotifier {
  FoodSaveLocationService._();
  static final FoodSaveLocationService instance = FoodSaveLocationService._();

  /// Re-sync the server copy at most this often when the device didn't move.
  static const Duration resyncInterval = Duration(minutes: 5);

  /// A move larger than this always triggers a re-sync.
  static const double resyncDistanceKm = 0.2;

  /// GPS backend; replaced by a fake in tests.
  @visibleForTesting
  GeoBackend backend = const GeolocatorBackend();

  /// Clock (UTC); replaced in tests.
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now().toUtc();

  LocationResult? _last;
  DateTime? _lastSyncAt;
  ({double latitude, double longitude})? _lastSynced;
  bool _clearedOnServer = false;
  Future<LocationResult>? _inFlight;

  /// Last known result (null before the first [refresh]).
  LocationResult? get last => _last;

  /// Forgets everything (logout, tests).
  void reset() {
    _last = null;
    _lastSyncAt = null;
    _lastSynced = null;
    _clearedOnServer = false;
    _inFlight = null;
    notifyListeners();
  }

  /// Asks permission if needed, reads the GPS, pushes the position to the
  /// server (PUT /foodsave/location). Never throws.
  Future<LocationResult> refresh(FoodSaveApi api, {bool askPermission = true}) {
    return _inFlight ??= _refresh(api, askPermission)
        .whenComplete(() => _inFlight = null);
  }

  Future<LocationResult> _refresh(FoodSaveApi api, bool askPermission) async {
    final result = await currentPosition(askPermission: askPermission);
    if (result.hasPosition) {
      await _syncIfNeeded(api, result.latitude!, result.longitude!);
    } else if (result.issue == LocationIssue.permissionDeniedForever &&
        !_clearedOnServer) {
      try {
        await api.clearMyLocation();
        _clearedOnServer = true;
        _lastSynced = null;
        _lastSyncAt = null;
      } catch (e) {
        developer.log('clearMyLocation failed: $e', name: 'foodsave.location');
      }
    }
    return result;
  }

  Future<void> _syncIfNeeded(FoodSaveApi api, double lat, double lng) async {
    final now = clock();
    final previous = _lastSynced;
    final stale = _lastSyncAt == null ||
        now.difference(_lastSyncAt!) > resyncInterval;
    final moved = previous == null ||
        haversineKm(previous.latitude, previous.longitude, lat, lng) >
            resyncDistanceKm;
    if (!stale && !moved) return;
    try {
      await api.updateMyLocation(lat, lng);
      _lastSyncAt = now;
      _lastSynced = (latitude: lat, longitude: lng);
      _clearedOnServer = false;
    } catch (e) {
      // Offline / server down: the next refresh() retries.
      developer.log('updateMyLocation failed: $e', name: 'foodsave.location');
    }
  }

  /// Reads the GPS only (no server sync) — e.g. a merchant locating a store.
  Future<LocationResult> currentPosition({bool askPermission = true}) async {
    LocationResult result;
    try {
      result = await _read(askPermission);
    } catch (e) {
      developer.log('GPS read failed: $e', name: 'foodsave.location');
      result = const LocationResult(issue: LocationIssue.unavailable);
    }
    _last = result;
    notifyListeners();
    return result;
  }

  Future<LocationResult> _read(bool askPermission) async {
    if (!await backend.isServiceEnabled()) {
      return const LocationResult(issue: LocationIssue.serviceDisabled);
    }
    var permission = await backend.checkPermission();
    if (permission == GeoPermission.denied && askPermission) {
      permission = await backend.requestPermission();
    }
    switch (permission) {
      case GeoPermission.denied:
        return const LocationResult(issue: LocationIssue.permissionDenied);
      case GeoPermission.deniedForever:
        return const LocationResult(
            issue: LocationIssue.permissionDeniedForever);
      case GeoPermission.granted:
        break;
    }

    ({double latitude, double longitude})? fix;
    try {
      fix = await backend.currentPosition();
    } catch (e) {
      developer.log('getCurrentPosition failed: $e', name: 'foodsave.location');
    }
    if (fix == null || !isValidLatLng(fix.latitude, fix.longitude)) {
      try {
        fix = await backend.lastKnownPosition();
      } catch (e) {
        developer.log('getLastKnownPosition failed: $e',
            name: 'foodsave.location');
        fix = null;
      }
    }
    if (fix == null || !isValidLatLng(fix.latitude, fix.longitude)) {
      return const LocationResult(issue: LocationIssue.unavailable);
    }
    return LocationResult(latitude: fix.latitude, longitude: fix.longitude);
  }

  /// Opens the system settings for location / app permissions.
  Future<void> openSettings(LocationIssue issue) async {
    try {
      if (issue == LocationIssue.serviceDisabled) {
        await backend.openLocationSettings();
      } else {
        await backend.openAppSettings();
      }
    } catch (e) {
      developer.log('openSettings failed: $e', name: 'foodsave.location');
    }
  }

  /// French, corrective explanation of [issue] for banners / snackbars.
  static String messageFor(LocationIssue issue) => switch (issue) {
        LocationIssue.serviceDisabled =>
          'La localisation de votre appareil est désactivée. Activez-la pour voir les paniers proches.',
        LocationIssue.permissionDenied =>
          'Autorisez l\'accès à votre position pour voir les paniers près de chez vous.',
        LocationIssue.permissionDeniedForever =>
          'L\'accès à la position est bloqué. Autorisez-le dans les paramètres de l\'application.',
        LocationIssue.unavailable =>
          'Position introuvable pour le moment. Réessayez dans un endroit dégagé.',
      };
}
