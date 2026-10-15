import 'package:proxilife_shared/proxilife_shared.dart';

import '../../api_error.dart';
import '../foodsave_context.dart';
import '../foodsave_mappers.dart';
import 'catalog_input.dart';

/// A client position (query parameters or last stored location).
typedef LatLng = ({double latitude, double longitude});

/// Client-side catalogue: available baskets around a position.
class FoodSaveCatalogQueryService {
  FoodSaveCatalogQueryService(this.ctx);

  final FoodSaveContext ctx;

  static const int _maxResults = 300;
  static const double _maxRadiusKm = 100;

  static const String _storeColumns =
      'c.id AS commerce_id, c.nom AS commerce_nom, '
      'c.adresse AS commerce_adresse, c.latitude AS commerce_latitude, '
      'c.longitude AS commerce_longitude, c.categorie AS commerce_categorie';

  /// Position from `lat`/`lng` query parameters when valid, else the
  /// caller's stored location, else null.
  Future<LatLng?> resolvePosition(
      int userId, Map<String, String> params) async {
    final lat = double.tryParse(params['lat'] ?? '');
    final lng = double.tryParse(params['lng'] ?? '');
    if (lat != null && lng != null && isValidLatLng(lat, lng)) {
      return (latitude: lat, longitude: lng);
    }
    final rows = await ctx.db.query('localisation_client',
        where: 'utilisateur_id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return null;
    return (
      latitude: (rows.first['latitude'] as num).toDouble(),
      longitude: (rows.first['longitude'] as num).toDouble(),
    );
  }

  /// `GET /foodsave/baskets` — only baskets a client can reserve right now.
  Future<List<BasketDto>> search(
      int userId, Map<String, String> params) async {
    final position = await resolvePosition(userId, params);

    double? radius;
    final rawRadius = params['rayon_km'];
    if (rawRadius != null && rawRadius.isNotEmpty) {
      radius = double.tryParse(rawRadius);
      if (radius == null ||
          !radius.isFinite ||
          radius <= 0 ||
          radius > _maxRadiusKm) {
        throw ApiError.badRequest(
            'Rayon de recherche invalide (entre 0 et 100 km)');
      }
    }
    final rawCategory = params['categorie'];
    final category = rawCategory == null || rawCategory.isEmpty
        ? null
        : parseCategory(rawCategory);
    final rawSort = params['tri'];
    final sort = rawSort == null || rawSort.isEmpty
        ? BasketSort.distance
        : parseBasketSort(rawSort);
    var query = (params['q'] ?? '').trim();
    if (query.length > 100) query = query.substring(0, 100);

    final now = ctx.now();
    final where = <String>[
      "p.statut = 'disponible'",
      'p.quantite > 0',
      'p.date_expiration > ?',
      'p.creneau_retrait_fin > ?',
    ];
    final args = <Object?>[
      isoUtc(now),
      isoUtc(now.add(foodSaveMinPickupLead)),
    ];
    if (category != null) {
      where.add('p.categorie = ?');
      args.add(category.apiValue);
    }
    if (query.isNotEmpty) {
      final like = '%${escapeLike(query)}%';
      where.add(r"(p.titre LIKE ? ESCAPE '\' OR p.contenu LIKE ? ESCAPE '\' "
          r"OR c.nom LIKE ? ESCAPE '\')");
      args.addAll([like, like, like]);
    }
    final rows = await ctx.db.rawQuery(
      'SELECT p.*, $_storeColumns FROM panier p '
      'JOIN commerce c ON c.commercant_id = p.commercant_id '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY p.cree_le DESC, p.id DESC LIMIT $_maxResults',
      args,
    );

    // Index = recency rank, used as the final tie-breaker (stable order).
    final entries = <({int rank, BasketDto basket, double? distance})>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final store = _storeFromAliased(row);
      final distance = position == null
          ? null
          : haversineKm(position.latitude, position.longitude,
              store.latitude, store.longitude);
      if (radius != null && distance != null && distance > radius) continue;
      entries.add((
        rank: i,
        distance: distance,
        basket: basketFromRow(row,
            store: store, distanceKm: _roundKm(distance)),
      ));
    }

    int byDistance(
        ({int rank, BasketDto basket, double? distance}) a,
        ({int rank, BasketDto basket, double? distance}) b) {
      final da = a.distance, db = b.distance;
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    }

    entries.sort((a, b) {
      var c = 0;
      switch (sort) {
        case BasketSort.distance:
          c = byDistance(a, b);
        case BasketSort.prix:
          c = a.basket.prixCentimes.compareTo(b.basket.prixCentimes);
          if (c == 0) c = byDistance(a, b);
        case BasketSort.reduction:
          c = _discount(b.basket).compareTo(_discount(a.basket));
          if (c == 0) {
            c = a.basket.prixCentimes.compareTo(b.basket.prixCentimes);
          }
      }
      return c != 0 ? c : a.rank.compareTo(b.rank);
    });
    return entries.map((e) => e.basket).toList();
  }

  /// `GET /foodsave/baskets/<id>` — any status, with store and distance.
  Future<BasketDto> getById(
      int userId, int basketId, Map<String, String> params) async {
    final rows = await ctx.db.rawQuery(
      'SELECT p.*, $_storeColumns FROM panier p '
      'LEFT JOIN commerce c ON c.commercant_id = p.commercant_id '
      'WHERE p.id = ?',
      [basketId],
    );
    if (rows.isEmpty) throw ApiError.notFound('Panier introuvable');
    final row = rows.first;
    final store = row['commerce_id'] == null ? null : _storeFromAliased(row);
    final position = await resolvePosition(userId, params);
    final distance = position == null || store == null
        ? null
        : haversineKm(position.latitude, position.longitude, store.latitude,
            store.longitude);
    return basketFromRow(row, store: store, distanceKm: _roundKm(distance));
  }

  static int _discount(BasketDto b) =>
      FoodSaveRules.discountPercent(b.prixCentimes, b.prixInitialCentimes);

  static double? _roundKm(double? km) =>
      km == null ? null : (km * 100).roundToDouble() / 100;

  static StoreDto _storeFromAliased(Map<String, Object?> row) => StoreDto(
        id: row['commerce_id'] as int,
        commercantId: row['commercant_id'] as int,
        nom: row['commerce_nom'] as String,
        adresse: row['commerce_adresse'] as String,
        latitude: (row['commerce_latitude'] as num).toDouble(),
        longitude: (row['commerce_longitude'] as num).toDouble(),
        categorie: FoodCategory.parse(row['commerce_categorie'] as String),
      );
}
