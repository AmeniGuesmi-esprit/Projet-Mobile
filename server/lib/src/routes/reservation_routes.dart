import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../services/reservation_service.dart';

/// Reservation routes (mounted behind [requireAuth]).
///
///  POST /trips/<id>/reservations   body: {"nb_places": 1}   (passenger)
///  GET  /reservations/mine                                   (passenger)
///  GET  /reservations/received                               (driver)
///  POST /reservations/<id>/accept | refuse                   (driver)
///  POST /reservations/<id>/cancel                            (passenger)
///  GET  /trips/<id>/boarding-code                            (driver)
///  POST /reservations/<id>/board   body: {code, methode, lat, lng}  (passenger)
Router buildReservationRoutes(ReservationService reservations) {
  final router = Router();

  router.post('/trips/<id|[0-9]+>/reservations', (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final raw = body['nb_places'];
      final nbPlaces = raw is num ? raw.toInt() : 1;
      final dto =
          await reservations.request(request.userId, int.parse(id), nbPlaces);
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/reservations/mine', (Request request) {
    return guard(() async {
      final list = await reservations.listMine(request.userId);
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  router.get('/reservations/received', (Request request) {
    return guard(() async {
      final list = await reservations.listReceived(request.userId);
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  router.post('/reservations/<id|[0-9]+>/accept', (Request request, String id) {
    return guard(() async {
      final dto = await reservations.accept(request.userId, int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/reservations/<id|[0-9]+>/refuse', (Request request, String id) {
    return guard(() async {
      final dto = await reservations.refuse(request.userId, int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/reservations/<id|[0-9]+>/cancel', (Request request, String id) {
    return guard(() async {
      final dto = await reservations.cancel(request.userId, int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.get('/trips/<id|[0-9]+>/boarding-code', (Request request, String id) {
    return guard(() async {
      final dto = await reservations.boardingCode(request.userId, int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/reservations/<id|[0-9]+>/board', (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final code = body['code'];
      if (code is! String || code.trim().isEmpty) {
        throw ApiError.badRequest('code requis');
      }
      final method = body['methode'] is String
          ? BoardingMethod.tryParse(body['methode'] as String)
          : null;
      if (method == null) {
        throw ApiError.badRequest('methode invalide (qr ou bluetooth)');
      }
      final lat = body['lat'];
      final lng = body['lng'];
      final dto = await reservations.confirmBoarding(
        request.userId,
        int.parse(id),
        code: code,
        method: method,
        lat: lat is num ? lat.toDouble() : null,
        lng: lng is num ? lng.toDouble() : null,
      );
      return jsonResponse(dto.toJson());
    });
  });

  return router;
}
