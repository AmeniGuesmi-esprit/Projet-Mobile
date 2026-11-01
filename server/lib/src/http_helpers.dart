import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shelf/shelf.dart';

import 'api_error.dart';

Response jsonResponse(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response errorJson(int status, String message) =>
    jsonResponse({'error': message}, status: status);

/// Reads and decodes a JSON request body. Throws [ApiError.badRequest] when
/// the body is not a JSON object.
Future<Map<String, dynamic>> readJsonBody(Request request) async {
  final raw = await request.readAsString();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  } on FormatException {
    throw ApiError.badRequest('Corps de requête JSON invalide');
  }
}

/// Runs [handler] and maps errors to JSON error responses.
Future<Response> guard(Future<Response> Function() handler) async {
  try {
    return await handler();
  } on ApiError catch (e) {
    return errorJson(e.statusCode, e.message);
  } on FormatException {
    return errorJson(400, 'Corps de requête JSON invalide');
  } on ArgumentError {
    return errorJson(400, 'Paramètre invalide');
  } catch (e, st) {
    // Never leak internals to the client, but log for the operator.
    developer.log('Unhandled error', error: e, stackTrace: st, name: 'proxilife');
    return errorJson(500, 'Erreur interne du serveur');
  }
}
