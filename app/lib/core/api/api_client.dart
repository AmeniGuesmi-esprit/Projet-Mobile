import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Error returned by the ProxiLife server (message is user-facing French).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin JSON-over-HTTP client for the local ProxiLife server.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8080',
            );

  final http.Client _http;

  /// Default: the Android emulator alias for the host machine.
  final String baseUrl;

  /// Bearer token for authenticated calls; set by the SessionController.
  String? token;

  Future<Map<String, dynamic>> getJson(String path) =>
      _send('GET', path, null);
  /// [timeout] overrides [defaultTimeout] (e.g. login: the server hashes the
  /// password with PBKDF2, which takes seconds on a slow machine).
  Future<Map<String, dynamic>> postJson(String path,
          [Map<String, dynamic>? body, Duration? timeout]) =>
      _send('POST', path, body, timeout);
  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body);
  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body);
  Future<Map<String, dynamic>> deleteJson(String path, [Map<String, dynamic>? body]) =>
      _send('DELETE', path, body);

  /// Time limit for ordinary requests.
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Time limit for requests that hash a password on the server.
  static const Duration passwordTimeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> _send(
    String verb,
    String path,
    Map<String, dynamic>? body, [
    Duration? timeout,
  ]) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$baseUrl$path');

    final http.Response response;
    try {
      final future = switch (verb) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: jsonEncode(body)),
        'PATCH' => _http.patch(uri, headers: headers, body: jsonEncode(body)),
        'PUT' => _http.put(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _http.delete(uri, headers: headers, body: jsonEncode(body)),
        _ => throw ArgumentError('Unsupported verb $verb'),
      };
      response = await future.timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw const ApiException(0,
          'Serveur local indisponible : vérifiez qu\'il est lancé puis réessayez');
    } on SocketException {
      throw const ApiException(0,
          'Serveur local indisponible : vérifiez qu\'il est lancé puis réessayez');
    } on http.ClientException {
      throw const ApiException(0,
          'Connexion impossible : vérifiez votre réseau puis réessayez');
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded['error'] as String? ?? 'Erreur inconnue (${response.statusCode})',
      );
    }
    return decoded;
  }
}
