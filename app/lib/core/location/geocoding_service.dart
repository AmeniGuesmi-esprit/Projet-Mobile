import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A place chosen by the user: a readable label and GPS coordinates.
class GeoPlace {
  const GeoPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

/// User-facing (French) geocoding error.
class GeocodingException implements Exception {
  const GeocodingException(this.message);

  final String message;

  @override
  String toString() => 'GeocodingException: $message';
}

/// Address <-> coordinates through OpenStreetMap Nominatim (free, no API key).
///
/// Usage policy: at most one request per second and a real User-Agent. The app
/// only searches when the user taps the search button (never while typing).
class GeocodingService {
  GeocodingService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const String _host = 'nominatim.openstreetmap.org';
  static const Map<String, String> _headers = {
    'User-Agent': 'ProxiLife/1.0 (projet etudiant Esprit)',
    'Accept-Language': 'fr',
  };

  /// Up to 5 matches in Tunisia and France (the countries the app supports).
  Future<List<GeoPlace>> search(String query) async {
    final uri = Uri.https(_host, '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '5',
      'countrycodes': 'tn,fr',
    });
    try {
      final response =
          await _http.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) {
        throw const GeocodingException('Recherche d\'adresse indisponible');
      }
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return GeoPlace(
          label: shortLabel(m['display_name'] as String),
          latitude: double.parse(m['lat'] as String),
          longitude: double.parse(m['lon'] as String),
        );
      }).toList();
    } on GeocodingException {
      rethrow;
    } on Exception {
      throw const GeocodingException(
          'Recherche impossible : vérifiez votre connexion internet');
    }
  }

  /// Address of a GPS point, or `null` when it cannot be resolved (the caller
  /// then falls back to a generic label — never an error).
  Future<GeoPlace?> reverse(double latitude, double longitude) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': '$latitude',
      'lon': '$longitude',
      'format': 'jsonv2',
      'zoom': '17',
    });
    try {
      final response =
          await _http.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final m = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final name = m['display_name'];
      if (name is! String) return null;
      return GeoPlace(
        label: shortLabel(name),
        latitude: latitude,
        longitude: longitude,
      );
    } on Exception {
      return null;
    }
  }

  static const Duration _timeout = Duration(seconds: 10);

  /// "Rue X, Quartier, Ville, Gouvernorat, Pays" -> first 3 parts, max 100
  /// characters (the server accepts at most 120).
  static String shortLabel(String displayName) {
    final parts = displayName
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    var label = parts.take(3).join(', ');
    if (label.length > 100) label = '${label.substring(0, 97)}...';
    return label;
  }
}
