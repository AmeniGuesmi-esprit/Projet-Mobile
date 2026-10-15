import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../api_error.dart';
import '../../auth/auth_middleware.dart';
import '../../http_helpers.dart';
import '../foodsave_context.dart';
import '../services/basket_service.dart';
import '../services/catalog_image_store.dart';
import '../services/catalog_input.dart';
import '../services/catalog_query_service.dart';
import '../services/catalog_stats_service.dart';

/// Stores, merchant baskets, photos, client catalogue and merchant stats.
Router buildFoodSaveCatalogRoutes(FoodSaveContext ctx) {
  final baskets = FoodSaveBasketService(ctx);
  final catalog = FoodSaveCatalogQueryService(ctx);
  final stats = FoodSaveStatsService(ctx);
  final router = Router();

  /// Runs [handler] for a merchant only (403 otherwise).
  Future<Response> merchant(
          Request request, Future<Response> Function(int merchantId) handler) =>
      guard(() async {
        requireMerchant(request.userRow);
        return handler(request.userId);
      });

  // ------------------------------------------------------------------ store

  router.get('/foodsave/store', (Request request) {
    return merchant(request, (id) async {
      final store = await baskets.stores.getMine(id);
      return jsonResponse(store.toJson());
    });
  });

  router.put('/foodsave/store', (Request request) {
    return merchant(request, (id) async {
      final body = await readJsonBody(request);
      final store = await baskets.stores.upsert(id, body);
      return jsonResponse(store.toJson());
    });
  });

  // ------------------------------------------------------- merchant baskets

  router.get('/foodsave/merchant/baskets', (Request request) {
    return merchant(request, (id) async {
      final raw = request.url.queryParameters['statut'];
      final statut =
          raw == null || raw.isEmpty ? null : parseBasketStatus(raw);
      final list = await baskets.listMine(id, statut: statut);
      return jsonResponse({'items': list.map((b) => b.toJson()).toList()});
    });
  });

  router.post('/foodsave/merchant/baskets', (Request request) {
    return merchant(request, (id) async {
      final body = await readJsonBody(request);
      final result = await baskets.create(id, body);
      return jsonResponse({
        'panier': result.panier.toJson(),
        'clients_notifies': result.clientsNotifies,
      }, status: 201);
    });
  });

  router.get('/foodsave/merchant/baskets/<basketId|[0-9]+>',
      (Request request, String basketId) {
    return merchant(request, (id) async {
      final basket = await baskets.getMine(id, int.parse(basketId));
      return jsonResponse(basket.toJson());
    });
  });

  router.patch('/foodsave/merchant/baskets/<basketId|[0-9]+>',
      (Request request, String basketId) {
    return merchant(request, (id) async {
      final body = await readJsonBody(request);
      final basket = await baskets.update(id, int.parse(basketId), body);
      return jsonResponse(basket.toJson());
    });
  });

  router.post('/foodsave/merchant/baskets/<basketId|[0-9]+>/cancel',
      (Request request, String basketId) {
    return merchant(request, (id) async {
      final basket = await baskets.cancel(id, int.parse(basketId));
      return jsonResponse(basket.toJson());
    });
  });

  router.delete('/foodsave/merchant/baskets/<basketId|[0-9]+>',
      (Request request, String basketId) {
    return merchant(request, (id) async {
      await baskets.delete(id, int.parse(basketId));
      return Response(204);
    });
  });

  router.post('/foodsave/merchant/baskets/<basketId|[0-9]+>/image',
      (Request request, String basketId) {
    return merchant(request, (id) async {
      final bytes = await readLimitedBytes(request.read(),
          declaredLength: request.contentLength);
      final basket = await baskets.setImage(id, int.parse(basketId),
          contentType: request.headers['content-type'], bytes: bytes);
      return jsonResponse(basket.toJson());
    });
  });

  router.get('/foodsave/merchant/stats', (Request request) {
    return merchant(request, (id) async {
      final dto = await stats.forMerchant(id);
      return jsonResponse(dto.toJson());
    });
  });

  // ----------------------------------------------------------------- images

  router.get('/foodsave/images/<name>', (Request request, String name) {
    return guard(() async {
      if (!basketImageNamePattern.hasMatch(name)) {
        throw ApiError.badRequest('Nom d\'image invalide');
      }
      final file = baskets.images.fileFor(name);
      if (file == null) throw ApiError.notFound('Image introuvable');
      final bytes = await file.readAsBytes();
      return Response.ok(bytes, headers: {
        'content-type': BasketImageStore.contentTypeFor(name),
        'content-length': '${bytes.length}',
        'cache-control': 'private, max-age=86400',
        'x-content-type-options': 'nosniff',
      });
    });
  });

  // ------------------------------------------------------- client catalogue

  router.get('/foodsave/baskets', (Request request) {
    return guard(() async {
      final list = await catalog.search(
          request.userId, request.url.queryParameters);
      return jsonResponse({'items': list.map((b) => b.toJson()).toList()});
    });
  });

  router.get('/foodsave/baskets/<basketId|[0-9]+>',
      (Request request, String basketId) {
    return guard(() async {
      final basket = await catalog.getById(request.userId,
          int.parse(basketId), request.url.queryParameters);
      return jsonResponse(basket.toJson());
    });
  });

  return router;
}
