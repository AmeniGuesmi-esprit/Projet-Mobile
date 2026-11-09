import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:proxilife_shared/proxilife_shared.dart';

/// Finds coordinates for a typed address. Returns null when the service is
/// unreachable, an empty list when nothing matches.
abstract class AddressGeocoder {
  Future<List<GeocodeResultDto>?> search(String query);
}

/// OpenStreetMap Nominatim. Usage policy: identify the app, at most one
/// request per second, cache results, and no search-as-you-type: the app only
/// calls this when the user presses the "Localiser" button.
class NominatimAddressSearch implements AddressGeocoder {
  NominatimAddressSearch({
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  static const String _userAgent = 'ProxiLife/0.1 (ServiceNow, serveur local)';
  static const Duration _minInterval = Duration(seconds: 1);
  static const int _maxCacheEntries = 500;

  final Map<String, List<GeocodeResultDto>> _cache = {};
  Future<void> _queue = Future<void>.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<GeocodeResultDto>?> search(String query) {
    final key = query.trim().toLowerCase();
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    // Serialised so that two calls are always at least a second apart.
    final result = _queue.then((_) async {
      final wait = _minInterval - DateTime.now().difference(_lastCall);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastCall = DateTime.now();
      final found = await _fetch(query);
      // Failures are not cached: the next try may succeed.
      if (found != null) {
        if (_cache.length >= _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        _cache[key] = found;
      }
      return found;
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<GeocodeResultDto>?> _fetch(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': query,
      'countrycodes': 'tn',
      'limit': '5',
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
            name: 'servicenow');
        return null;
      }
      return parseNominatimSearch(jsonDecode(body));
    } catch (e) {
      developer.log('Nominatim unreachable: $e', name: 'servicenow');
      return null;
    }
  }
}

/// Addresses of a Nominatim `/search` answer; ignores malformed entries.
List<GeocodeResultDto> parseNominatimSearch(Object? json) {
  if (json is! List) return const [];
  final results = <GeocodeResultDto>[];
  for (final item in json) {
    if (item is! Map<String, dynamic>) continue;
    final label = item['display_name'];
    final latitude = double.tryParse('${item['lat']}');
    final longitude = double.tryParse('${item['lon']}');
    if (label is String && latitude != null && longitude != null) {
      results.add(GeocodeResultDto(
        label: label,
        latitude: latitude,
        longitude: longitude,
      ));
    }
  }
  return results;
}
