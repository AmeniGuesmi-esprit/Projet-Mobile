import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../api_error.dart';
import '../../auth/auth_middleware.dart';
import '../../http_helpers.dart';
import '../foodsave_context.dart';
import '../services/reservation_service.dart';

/// Reservation, payment, QR and scan routes (mounted behind requireAuth).
Router buildFoodSaveReservationRoutes(FoodSaveContext ctx) {
  final service = FoodSaveReservationService(ctx);
  final router = Router();

  // ---- Client ----

  router.post('/foodsave/reservations', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.reserve(
        clientId: request.userId,
        panierId: _requiredInt(body, 'panier_id', 'Panier manquant'),
        quantite: _requiredInt(body, 'quantite', 'Quantité invalide'),
        moyenPaiementId: _optionalInt(
            body, 'moyen_paiement_id', 'Moyen de paiement invalide'),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/foodsave/reservations', (Request request) {
    return guard(() async {
      final list = await service.listForClient(request.userId);
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  router.get('/foodsave/reservations/<id|[0-9]+>',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.getForViewer(_parseId(id),
          viewerId: request.userId);
      if (dto == null) throw ApiError.notFound('Réservation introuvable');
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/foodsave/reservations/<id|[0-9]+>/cancel',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.cancelByClient(_parseId(id),
          clientId: request.userId);
      return jsonResponse(dto.toJson());
    });
  });

  // ---- Merchant ----

  router.get('/foodsave/merchant/reservations', (Request request) {
    return guard(() async {
      requireMerchant(request.userRow);
      final params = request.url.queryParameters;
      final panier = params['panier_id'];
      final statut = params['statut'];
      int? panierId;
      if (panier != null && panier.isNotEmpty) {
        panierId = int.tryParse(panier);
        if (panierId == null) throw ApiError.badRequest('Panier invalide');
      }
      final list = await service.listForMerchant(
        request.userId,
        panierId: panierId,
        statut: statut == null || statut.isEmpty
            ? null
            : ReservationStatus.parse(statut),
      );
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  router.post('/foodsave/merchant/scan', (Request request) {
    return guard(() async {
      requireMerchant(request.userRow);
      final body = await readJsonBody(request);
      final token = body['token'];
      if (token is! String || token.trim().isEmpty) {
        throw ApiError.badRequest('QR code manquant');
      }
      final result = await service.scan(request.userId, token);
      return jsonResponse(result.toJson());
    });
  });

  return router;
}

int _parseId(String raw) {
  final id = int.tryParse(raw);
  if (id == null) throw ApiError.notFound('Réservation introuvable');
  return id;
}

int _requiredInt(Map<String, dynamic> body, String key, String message) {
  final value = body[key];
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw ApiError.badRequest(message);
}

int? _optionalInt(Map<String, dynamic> body, String key, String message) =>
    body[key] == null ? null : _requiredInt(body, key, message);
