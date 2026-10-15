import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// Turns GPS coordinates into a postal address (French), or null when the
/// place is unknown / the service is unreachable.
abstract class ReverseGeocoder {
  Future<String?> reverse(double latitude, double longitude);
}

/// OpenStreetMap Nominatim (https://nominatim.org). Usage policy: identify
/// the app in the User-Agent, at most 1 request per second, cache results.
class NominatimGeocoder implements ReverseGeocoder {
  NominatimGeocoder(
      {HttpClient? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  static const String _userAgent = 'ProxiLife/0.1 (FoodSave, serveur local)';
  static const Duration _minInterval = Duration(seconds: 1);
  static const int _maxCacheEntries = 500;

  /// Keyed by coordinates rounded to ~1 m (5 decimals).
  final Map<String, String?> _cache = {};
  Future<void> _queue = Future<void>.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<String?> reverse(double latitude, double longitude) {
    final key =
        '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    // Serialised so that two calls are always >= 1 s apart.
    final result = _queue.then((_) async {
      if (_cache.containsKey(key)) return _cache[key];
      final wait = _minInterval - DateTime.now().difference(_lastCall);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastCall = DateTime.now();
      final address = await _fetch(latitude, longitude);
      if (_cache.length >= _maxCacheEntries) _cache.remove(_cache.keys.first);
      _cache[key] = address;
      return address;
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> _fetch(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '$latitude',
      'lon': '$longitude',
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'fr',
    });
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        developer.log('Nominatim HTTP ${response.statusCode}',
            name: 'foodsave');
        return null;
      }
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? formatNominatimAddress(json) : null;
    } catch (e) {
      developer.log('Nominatim unreachable: $e', name: 'foodsave');
      return null;
    }
  }
}

/// "12 Rue de Marseille, Lafayette, Tunis" from a Nominatim reverse result:
/// street (with number), neighbourhood, city. Falls back to the first parts
/// of `display_name`. Null when nothing usable (e.g. in the sea).
String? formatNominatimAddress(Map<String, dynamic> json) {
  final a = json['address'];
  final parts = <String>[];
  if (a is Map<String, dynamic>) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final road = pick(['road', 'pedestrian', 'footway', 'square']);
    final number = pick(['house_number']);
    if (road != null) parts.add(number == null ? road : '$number $road');
    final area = pick(['neighbourhood', 'suburb', 'quarter', 'city_district']);
    if (area != null) parts.add(area);
    final city = pick(['city', 'town', 'village', 'municipality', 'state']);
    if (city != null && !parts.contains(city)) parts.add(city);
  }
  if (parts.isEmpty) {
    final display = json['display_name'];
    if (display is String && display.trim().isNotEmpty) {
      parts.addAll(display.split(',').map((s) => s.trim()).take(3));
    }
  }
  if (parts.isEmpty) return null;
  final address = parts.join(', ');
  return address.length > 200 ? address.substring(0, 200).trim() : address;
}
