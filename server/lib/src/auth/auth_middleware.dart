import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';

import '../http_helpers.dart';
import 'session_service.dart';

/// Paths that never require a Bearer token.
const Set<String> publicPaths = {
  '/health',
  '/auth/register',
  '/auth/verify',
  '/auth/resend',
  '/auth/login',
};

/// Bearer-token authentication middleware. Public paths pass through; other
/// requests need a valid session. On success the user row is available in the
/// request context, see [SessionContext].
Middleware requireAuth(SessionService sessions) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (publicPaths.contains(request.requestedUri.path)) {
        return innerHandler(request);
      }
      final header = request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        return errorJson(401, 'Authentification requise');
      }
      final token = header.substring('Bearer '.length).trim();
      final user = await sessions.resolveUser(token);
      if (user == null) {
        return errorJson(401, 'Session expirée, veuillez vous reconnecter');
      }
      if (AccountStatus.parse(user['statut_compte'] as String) !=
          AccountStatus.actif) {
        return errorJson(403, 'Compte non actif');
      }
      return innerHandler(request.change(context: {
        SessionKeys.userId: user['id'] as int,
        SessionKeys.userRow: user,
        SessionKeys.token: token,
      }));
    };
  };
}

abstract class SessionKeys {
  static const String userId = 'proxilife.userId';
  static const String userRow = 'proxilife.userRow';
  static const String token = 'proxilife.token';
}

extension SessionContext on Request {
  int get userId => context[SessionKeys.userId]! as int;
  Map<String, Object?> get userRow =>
      context[SessionKeys.userRow]! as Map<String, Object?>;
  String get sessionToken => context[SessionKeys.token]! as String;
}
