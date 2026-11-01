/// Domain error mapped to an HTTP response with a French, user-facing message.
class ApiError implements Exception {
  const ApiError(this.statusCode, this.message);

  final int statusCode;
  final String message;

  factory ApiError.badRequest(String message) => ApiError(400, message);
  factory ApiError.unauthorized([String message = 'Authentification requise']) =>
      ApiError(401, message);
  factory ApiError.forbidden(String message) => ApiError(403, message);
  factory ApiError.notFound(String message) => ApiError(404, message);
  factory ApiError.conflict(String message) => ApiError(409, message);
  factory ApiError.gone(String message) => ApiError(410, message);

  @override
  String toString() => 'ApiError($statusCode): $message';
}
