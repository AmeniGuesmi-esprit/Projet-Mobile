import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../api_error.dart';
import '../../auth/auth_middleware.dart';
import '../../http_helpers.dart';
import '../foodsave_context.dart';
import '../services/geo_location_service.dart';

/// Client position + in-app notification routes (any authenticated role).
Router buildFoodSaveGeoRoutes(FoodSaveContext ctx) {
  final geo = FoodSaveGeoService(ctx);
  final router = Router();

  // ---- Position du client ----

  router.put('/foodsave/location', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final (latitude, longitude) = FoodSaveGeoService.parseLatLng(body);
      await geo.saveLocation(request.userId, latitude, longitude);
      return jsonResponse({'message': 'Position mise à jour'});
    });
  });

  router.get('/foodsave/location', (Request request) {
    return guard(() async {
      final location = await geo.getLocation(request.userId);
      if (location == null) {
        throw ApiError.notFound('Aucune position enregistrée');
      }
      return jsonResponse(location);
    });
  });

  router.delete('/foodsave/location', (Request request) {
    return guard(() async {
      await geo.clearLocation(request.userId);
      return Response(204);
    });
  });

  // ---- Notifications ----

  router.get('/foodsave/notifications', (Request request) {
    return guard(() async {
      final flag = request.url.queryParameters['non_lues'];
      final unreadOnly = flag == '1' || flag == 'true';
      final items =
          await geo.listNotifications(request.userId, unreadOnly: unreadOnly);
      return jsonResponse({'items': items.map((n) => n.toJson()).toList()});
    });
  });

  router.post('/foodsave/notifications/read-all', (Request request) {
    return guard(() async {
      final count = await geo.markAllRead(request.userId);
      return jsonResponse({
        'message': 'Toutes les notifications ont été marquées comme lues',
        'mises_a_jour': count,
      });
    });
  });

  router.post('/foodsave/notifications/<id|[0-9]+>/read',
      (Request request, String id) {
    return guard(() async {
      await geo.markRead(request.userId, int.parse(id));
      return jsonResponse({'message': 'Notification marquée comme lue'});
    });
  });

  return router;
}
