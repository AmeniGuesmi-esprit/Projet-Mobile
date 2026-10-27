import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../api_error.dart';
import '../../auth/auth_middleware.dart';
import '../../http_helpers.dart';
import '../foodsave_context.dart';
import '../services/geo_location_service.dart';

/// Longest client → store route we compute (km, straight line).
const double maxRouteKm = 200;

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

  // ---- Adresse d'une position (formulaire du commerce) ----

  router.get('/foodsave/geo/reverse', (Request request) {
    return guard(() async {
      final q = request.url.queryParameters;
      final lat = double.tryParse(q['lat'] ?? '');
      final lng = double.tryParse(q['lng'] ?? '');
      if (lat == null || lng == null || !isValidLatLng(lat, lng)) {
        throw ApiError.badRequest('Coordonnées GPS invalides');
      }
      final geocoder = ctx.geocoder;
      if (geocoder == null) {
        throw ApiError(503, 'Recherche d\'adresse indisponible');
      }
      final adresse = await geocoder.reverse(lat, lng);
      if (adresse == null) {
        throw ApiError.notFound('Aucune adresse trouvée pour cette position');
      }
      return jsonResponse({'adresse': adresse});
    });
  });

  // ---- Itinéraire client -> commerce (voiture / à pied) ----

  router.get('/foodsave/geo/route', (Request request) {
    return guard(() async {
      final q = request.url.queryParameters;
      double? read(String key) => double.tryParse(q[key] ?? '');
      final fromLat = read('from_lat');
      final fromLng = read('from_lng');
      final toLat = read('to_lat');
      final toLng = read('to_lng');
      if (fromLat == null ||
          fromLng == null ||
          toLat == null ||
          toLng == null ||
          !isValidLatLng(fromLat, fromLng) ||
          !isValidLatLng(toLat, toLng)) {
        throw ApiError.badRequest('Coordonnées GPS invalides');
      }
      final TravelMode mode;
      try {
        mode = TravelMode.parse(q['mode'] ?? TravelMode.voiture.apiValue);
      } on ArgumentError {
        throw ApiError.badRequest('Mode de trajet inconnu (voiture ou pied)');
      }
      if (haversineKm(fromLat, fromLng, toLat, toLng) > maxRouteKm) {
        throw ApiError.badRequest(
            'Ce commerce est trop loin pour calculer un itinéraire '
            '(plus de ${maxRouteKm.round()} km)');
      }
      final planner = ctx.routePlanner;
      if (planner == null) {
        throw ApiError(503, 'Calcul d\'itinéraire indisponible');
      }
      final route = await planner.route(
        fromLatitude: fromLat,
        fromLongitude: fromLng,
        toLatitude: toLat,
        toLongitude: toLng,
        mode: mode,
      );
      if (route == null) {
        throw ApiError(503,
            'Itinéraire indisponible pour le moment : réessayez plus tard');
      }
      return jsonResponse(route.toJson());
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
