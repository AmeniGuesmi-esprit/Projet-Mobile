import 'dart:async';
import 'dart:developer' as developer;

import 'package:shelf_router/shelf_router.dart';

import 'foodsave_context.dart';
import 'routes/catalog_routes.dart';
import 'routes/geo_routes.dart';
import 'routes/reservation_routes.dart';
import 'services/basket_service.dart';
import 'services/reservation_service.dart';

/// All FoodSave routes (mounted behind requireAuth by `buildApp`).
Router buildFoodSaveRouter(FoodSaveContext ctx) => Router()
  ..mount('/', buildFoodSaveCatalogRoutes(ctx).call)
  ..mount('/', buildFoodSaveGeoRoutes(ctx).call)
  ..mount('/', buildFoodSaveReservationRoutes(ctx).call);

/// Periodic maintenance: expire QR codes / baskets, warn before expiry.
/// Started by the real server only (tests call the services directly).
Timer startFoodSaveJobs(FoodSaveContext ctx,
    {Duration every = const Duration(seconds: 30)}) {
  final reservations = FoodSaveReservationService(ctx);
  final baskets = FoodSaveBasketService(ctx);
  var running = false;
  Future<void> tick() async {
    if (running) return; // never overlap two runs
    running = true;
    try {
      await reservations.warnExpiringSoon();
      await reservations.expireDue();
      await baskets.expireOutdatedBaskets();
    } catch (e, st) {
      developer.log('FoodSave job failed',
          error: e, stackTrace: st, name: 'foodsave');
    } finally {
      running = false;
    }
  }

  unawaited(tick());
  return Timer.periodic(every, (_) => tick());
}
