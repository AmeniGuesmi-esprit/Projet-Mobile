import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:proxilife_shared/proxilife_shared.dart';

/// Plans a route between two GPS points, or null when no route exists /
/// the routing service is unreachable.
abstract class RoutePlanner {
  Future<RouteDto?> route({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required TravelMode mode,
  });
}

/// OSRM on the FOSSGIS servers (routing.openstreetmap.de), which host a car
/// and a foot profile. Usage policy: identify the app, stay well under one
/// request per second, cache results.
class OsrmRoutePlanner implements RoutePlanner {
  OsrmRoutePlanner(
      {HttpClient? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  static const String _userAgent = 'ProxiLife/0.1 (FoodSave, serveur local)';
  static const Duration _minInterval = Duration(seconds: 1);
  static const int _maxCacheEntries = 200;

  /// Keyed by mode + coordinates rounded to ~10 m (4 decimals).
  final Map<String, RouteDto?> _cache = {};
  Future<void> _queue = Future<void>.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static String _profile(TravelMode mode) => switch (mode) {
        TravelMode.voiture => 'routed-car',
        TravelMode.pied => 'routed-foot',
      };

  @override
  Future<RouteDto?> route({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required TravelMode mode,
  }) {
    String r(double v) => v.toStringAsFixed(4);
    final key = '${mode.apiValue}:${r(fromLatitude)},${r(fromLongitude)}:'
        '${r(toLatitude)},${r(toLongitude)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final result = _queue.then((_) async {
      if (_cache.containsKey(key)) return _cache[key];
      final wait = _minInterval - DateTime.now().difference(_lastCall);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastCall = DateTime.now();
      final route = await _fetch(
          fromLatitude, fromLongitude, toLatitude, toLongitude, mode);
      // Failures are not cached: the next try may succeed.
      if (route != null) {
        if (_cache.length >= _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        _cache[key] = route;
      }
      return route;
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<RouteDto?> _fetch(double fromLat, double fromLng, double toLat,
      double toLng, TravelMode mode) async {
    // OSRM expects longitude,latitude.
    final uri = Uri.https(
      'routing.openstreetmap.de',
      '/${_profile(mode)}/route/v1/driving/$fromLng,$fromLat;$toLng,$toLat',
      {'overview': 'full', 'geometries': 'geojson'},
    );
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        developer.log('OSRM HTTP ${response.statusCode}', name: 'foodsave');
        return null;
      }
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? parseOsrmRoute(json, mode) : null;
    } catch (e) {
      developer.log('OSRM unreachable: $e', name: 'foodsave');
      return null;
    }
  }
}

/// First route of an OSRM `route` answer (GeoJSON geometry), or null.
RouteDto? parseOsrmRoute(Map<String, dynamic> json, TravelMode mode) {
  if (json['code'] != 'Ok') return null;
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty) return null;
  final first = routes.first;
  if (first is! Map<String, dynamic>) return null;
  final geometry = first['geometry'];
  final coordinates =
      geometry is Map<String, dynamic> ? geometry['coordinates'] : null;
  if (coordinates is! List || coordinates.length < 2) return null;
  final points = <(double, double)>[];
  for (final c in coordinates) {
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      // GeoJSON order is [longitude, latitude].
      points.add(((c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
  }
  final distance = first['distance'];
  final duration = first['duration'];
  if (points.length < 2 || distance is! num || duration is! num) return null;
  return RouteDto(
    mode: mode,
    distanceMetres: distance.round(),
    dureeSecondes: duration.round(),
    points: points,
  );
}
