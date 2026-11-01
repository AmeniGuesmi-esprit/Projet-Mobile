import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../services/auth_service.dart';

/// Public authentication routes (no Bearer token required).
Router buildAuthRoutes(AuthService auth) {
  final router = Router();

  router.post('/auth/register', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final role = UserRole.parse(body['role'] as String? ?? '');
      final id = await auth.register(
        nom: body['nom'] as String? ?? '',
        prenom: body['prenom'] as String? ?? '',
        email: body['email'] as String? ?? '',
        telephone: body['telephone'] as String? ?? '',
        motDePasse: body['mot_de_passe'] as String? ?? '',
        role: role,
        rib: body['rib'] as String?,
      );
      return jsonResponse(
        {'id': id, 'message': 'Compte créé : vérifiez votre e-mail'},
        status: 201,
      );
    });
  });

  router.post('/auth/verify', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      await auth.verify(
        body['email'] as String? ?? '',
        body['code'] as String? ?? '',
      );
      return jsonResponse({'message': 'Compte vérifié'});
    });
  });

  router.post('/auth/resend', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      await auth.resend(body['email'] as String? ?? '');
      return jsonResponse({'message': 'Nouveau code envoyé'});
    });
  });

  router.post('/auth/login', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final response = await auth.login(
        body['email'] as String? ?? '',
        body['mot_de_passe'] as String? ?? '',
      );
      return jsonResponse(response.toJson());
    });
  });

  return router;
}

/// POST /auth/logout — mounted inside the protected section of the app.
Future<Response> handleLogout(Request request, AuthService auth) {
  return guard(() async {
    await auth.logout(request.sessionToken);
    return Response(204);
  });
}
