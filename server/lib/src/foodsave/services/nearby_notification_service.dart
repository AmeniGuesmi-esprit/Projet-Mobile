import 'dart:math' as math;

import 'package:proxilife_shared/proxilife_shared.dart';

import '../foodsave_context.dart';

/// Client locations + "nouveau panier" notifications within 5 km.
class FoodSaveNearbyNotificationService {
  FoodSaveNearbyNotificationService(this.ctx);

  final FoodSaveContext ctx;

  static const String title = '🍱 Nouveau panier anti-gaspillage !';
  static const String baseMessage =
      'Un panier est disponible près de chez vous à prix réduit. '
      'Découvrez-le avant qu\'il ne soit épuisé !';

  /// Called by the catalog when a basket becomes `disponible` (creation /
  /// republication). Notifies every client whose last known position is
  /// within [foodSaveNotificationRadiusKm] of the store. Idempotent per
  /// (basket, client). Returns the number of clients newly notified.
  ///
  /// Must NOT be called from inside another sqflite transaction (it opens
  /// its own one to batch the inserts).
  Future<int> notifyNearbyClients(int basketId) async {
    final baskets = await ctx.db.rawQuery(
      'SELECT p.statut, p.quantite, p.date_expiration, p.commercant_id, '
      'c.nom AS commerce_nom, c.latitude, c.longitude '
      'FROM panier p JOIN commerce c ON c.commercant_id = p.commercant_id '
      'WHERE p.id = ?',
      [basketId],
    );
    if (baskets.isEmpty) return 0;
    final basket = baskets.first;
    if (basket['statut'] != BasketStatus.disponible.apiValue) return 0;
    if ((basket['quantite'] as int) <= 0) return 0;
    if ((basket['date_expiration'] as String).compareTo(ctx.nowIso()) <= 0) {
      return 0;
    }

    final storeLat = (basket['latitude'] as num).toDouble();
    final storeLng = (basket['longitude'] as num).toDouble();
    final merchantId = basket['commercant_id'] as int;
    final storeName = basket['commerce_nom'] as String;

    final box = GeoBoundingBox.around(
        storeLat, storeLng, foodSaveNotificationRadiusKm);
    final candidates = await ctx.db.rawQuery(
      'SELECT u.id, l.latitude, l.longitude '
      'FROM localisation_client l JOIN utilisateur u ON u.id = l.utilisateur_id '
      'WHERE u.role = ? AND u.statut_compte = ? AND u.id <> ? '
      'AND ${box.sqlWhere('l.latitude', 'l.longitude')}',
      [
        UserRole.client.apiValue,
        AccountStatus.actif.apiValue,
        merchantId,
        ...box.sqlArgs,
      ],
    );

    final nearby = <(int, double)>[];
    for (final row in candidates) {
      final km = haversineKm(storeLat, storeLng,
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble());
      if (km <= foodSaveNotificationRadiusKm) nearby.add((row['id'] as int, km));
    }
    if (nearby.isEmpty) return 0;

    var created = 0;
    await ctx.db.transaction((txn) async {
      for (final (userId, km) in nearby) {
        final isNew = await ctx.notifier.notifyUser(
          userId: userId,
          type: FoodSaveNotificationType.nouveauPanier,
          titre: title,
          message: '$baseMessage\n$storeName · à ${formatDistanceFr(km)}',
          panierId: basketId,
          cleEvenement: 'nouveau_panier:$basketId:user:$userId',
          executor: txn,
        );
        if (isNew) created++;
      }
      await ctx.journal.log(
        'notifications_envoyees',
        utilisateurId: merchantId,
        panierId: basketId,
        details: {
          'nouvelles': created,
          'clients_proches': nearby.length,
          'rayon_km': foodSaveNotificationRadiusKm,
        },
        executor: txn,
      );
    });
    return created;
  }
}

/// "0,6 km" / "850 m" (French decimal comma).
String formatDistanceFr(double km) {
  if (km < 1) {
    final m = (km * 1000 / 10).round() * 10;
    return '${math.max(m, 10)} m';
  }
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Cheap SQL prefilter for a radius search: a lat/lng rectangle that always
/// contains the circle; the exact distance is then checked with haversine.
class GeoBoundingBox {
  const GeoBoundingBox._(
      this.minLat, this.maxLat, this.minLng, this.maxLng, this.allLongitudes);

  /// [radiusKm] around ([lat], [lng]). Uses 111.32 km per degree with a 2 %
  /// safety margin (the haversine Earth radius gives ~111.19 km/degree).
  factory GeoBoundingBox.around(double lat, double lng, double radiusKm) {
    const kmPerDegree = 111.32;
    final r = radiusKm * 1.02;
    final dLat = r / kmPerDegree;
    final minLat = math.max(-90.0, lat - dLat);
    final maxLat = math.min(90.0, lat + dLat);
    // The box reaches a pole, or cos(lat) ~ 0: every longitude qualifies.
    final cosLat = math.cos(lat * math.pi / 180).abs();
    if (minLat <= -90 || maxLat >= 90 || cosLat < 1e-6) {
      return GeoBoundingBox._(minLat, maxLat, -180, 180, true);
    }
    final dLng = r / (kmPerDegree * cosLat);
    if (dLng >= 180) {
      return GeoBoundingBox._(minLat, maxLat, -180, 180, true);
    }
    return GeoBoundingBox._(minLat, maxLat, lng - dLng, lng + dLng, false);
  }

  final double minLat;
  final double maxLat;

  /// May fall outside [-180, 180] near the antimeridian (handled in SQL).
  final double minLng;
  final double maxLng;
  final bool allLongitudes;

  /// WHERE fragment using `?` placeholders, see [sqlArgs].
  String sqlWhere(String latColumn, String lngColumn) {
    final lat = '$latColumn BETWEEN ? AND ?';
    if (allLongitudes) return lat;
    if (minLng < -180 || maxLng > 180) {
      // Wraps around the antimeridian: two longitude ranges.
      return '$lat AND ($lngColumn >= ? OR $lngColumn <= ?)';
    }
    return '$lat AND $lngColumn BETWEEN ? AND ?';
  }

  List<Object> get sqlArgs {
    if (allLongitudes) return [minLat, maxLat];
    if (minLng < -180) return [minLat, maxLat, minLng + 360, maxLng];
    if (maxLng > 180) return [minLat, maxLat, minLng, maxLng - 360];
    return [minLat, maxLat, minLng, maxLng];
  }
}
