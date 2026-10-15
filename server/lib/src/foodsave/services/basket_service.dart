import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../api_error.dart';
import '../foodsave_context.dart';
import '../foodsave_mappers.dart';
import 'catalog_image_store.dart';
import 'catalog_input.dart';
import 'catalog_store_service.dart';
import 'nearby_notification_service.dart';
import 'reservation_service.dart';

/// Merchant-side basket lifecycle: creation, edition, cancellation,
/// deletion, photo, and the background expiry job.
class FoodSaveBasketService {
  FoodSaveBasketService(this.ctx)
      : stores = FoodSaveStoreService(ctx),
        images = BasketImageStore(ctx.uploadsDir);

  final FoodSaveContext ctx;
  final FoodSaveStoreService stores;
  final BasketImageStore images;

  static const String _activeCountSql =
      '(SELECT COUNT(*) FROM reservation r WHERE r.panier_id = p.id '
      "AND r.statut = 'en_attente') AS reservations_actives";

  static const String _openStatuses = "('disponible', 'epuise')";

  // ------------------------------------------------------------------ read

  /// The merchant's baskets, newest first, optionally filtered by status.
  Future<List<BasketDto>> listMine(int merchantId,
      {BasketStatus? statut}) async {
    final store = await stores.findByMerchant(merchantId);
    final rows = await ctx.db.rawQuery(
      'SELECT p.*, $_activeCountSql FROM panier p '
      'WHERE p.commercant_id = ?${statut == null ? '' : ' AND p.statut = ?'} '
      'ORDER BY p.cree_le DESC, p.id DESC',
      [merchantId, if (statut != null) statut.apiValue],
    );
    return rows
        .map((r) => basketFromRow(r,
            store: store,
            reservationsActives: r['reservations_actives'] as int))
        .toList();
  }

  /// One of the merchant's baskets; 404 when it belongs to someone else.
  Future<BasketDto> getMine(int merchantId, int basketId) async {
    final rows = await ctx.db.rawQuery(
      'SELECT p.*, $_activeCountSql FROM panier p '
      'WHERE p.id = ? AND p.commercant_id = ?',
      [basketId, merchantId],
    );
    if (rows.isEmpty) throw _notFound();
    return basketFromRow(rows.first,
        store: await stores.findByMerchant(merchantId),
        reservationsActives: rows.first['reservations_actives'] as int);
  }

  // ---------------------------------------------------------------- create

  /// Creates a basket and notifies nearby clients.
  Future<({BasketDto panier, int clientsNotifies})> create(
      int merchantId, Map<String, dynamic> body) async {
    final store = await stores.findByMerchant(merchantId);
    if (store == null) {
      throw ApiError.conflict(
          'Configurez d\'abord votre commerce avant de publier un panier');
    }
    final titre = reqString(body, 'titre');
    final contenu = reqString(body, 'contenu');
    final categorie = optCategory(body, 'categorie') ?? store.categorie;
    final prix = reqInt(body, 'prix_centimes');
    final prixInitial = reqInt(body, 'prix_initial_centimes');
    final quantite = reqInt(body, 'quantite');
    final debut = reqDate(body, 'creneau_retrait_debut');
    final fin = reqDate(body, 'creneau_retrait_fin');
    final expiration = reqDate(body, 'date_expiration');

    _validate(
      titre: titre,
      contenu: contenu,
      prix: prix,
      prixInitial: prixInitial,
      quantite: quantite,
      debut: debut,
      fin: fin,
      expiration: expiration,
    );
    if (quantite < 1) {
      throw ApiError.badRequest('La quantité doit être d\'au moins 1');
    }
    _requireFutureEnd(fin);

    final now = ctx.nowIso();
    final id = await ctx.db.transaction((txn) async {
      final id = await txn.insert('panier', {
        'titre': titre,
        'contenu': contenu,
        'categorie': categorie.apiValue,
        'image': null,
        'prix_centimes': prix,
        'prix_initial_centimes': prixInitial,
        'quantite': quantite,
        'quantite_initiale': quantite,
        'creneau_retrait_debut': isoUtc(debut),
        'creneau_retrait_fin': isoUtc(fin),
        'date_expiration': isoUtc(expiration),
        'statut': BasketStatus.disponible.apiValue,
        'commercant_id': merchantId,
        'cree_le': now,
        'mis_a_jour_le': now,
      });
      await ctx.journal.log('panier_cree',
          utilisateurId: merchantId,
          panierId: id,
          details: {'quantite': quantite, 'prix_centimes': prix},
          executor: txn);
      return id;
    });

    final notified = await _notifyNearby(id);
    return (panier: await getMine(merchantId, id), clientsNotifies: notified);
  }

  // ---------------------------------------------------------------- update

  /// Partial update. `quantite` is the new number of units on sale; units
  /// already reserved are never affected.
  Future<BasketDto> update(
      int merchantId, int basketId, Map<String, dynamic> body) async {
    var republished = false;
    await ctx.db.transaction((txn) async {
      final row = await _ownRow(txn, merchantId, basketId);
      final oldStatus = BasketStatus.parse(row['statut'] as String);
      if (!FoodSaveRules.isBasketEditable(oldStatus)) {
        throw ApiError.conflict(
            'Ce panier est clôturé (${oldStatus.label.toLowerCase()}) : '
            'il ne peut plus être modifié');
      }
      final oldQty = row['quantite'] as int;
      final titre = optString(body, 'titre') ?? row['titre'] as String;
      final contenu = optString(body, 'contenu') ?? row['contenu'] as String;
      final categorie = optCategory(body, 'categorie') ??
          FoodCategory.parse(row['categorie'] as String);
      final prix = optInt(body, 'prix_centimes') ?? row['prix_centimes'] as int;
      final prixInitial = optInt(body, 'prix_initial_centimes') ??
          row['prix_initial_centimes'] as int;
      final quantite = optInt(body, 'quantite') ?? oldQty;
      final newFin = optDate(body, 'creneau_retrait_fin');
      final debut = optDate(body, 'creneau_retrait_debut') ??
          DateTime.parse(row['creneau_retrait_debut'] as String);
      final fin =
          newFin ?? DateTime.parse(row['creneau_retrait_fin'] as String);
      final expiration = optDate(body, 'date_expiration') ??
          DateTime.parse(row['date_expiration'] as String);

      _validate(
        titre: titre,
        contenu: contenu,
        prix: prix,
        prixInitial: prixInitial,
        quantite: quantite,
        debut: debut,
        fin: fin,
        expiration: expiration,
      );
      if (newFin != null) _requireFutureEnd(newFin);

      var newStatus = oldStatus;
      if (quantite == 0) {
        newStatus = BasketStatus.epuise;
      } else if (oldStatus == BasketStatus.epuise) {
        newStatus = BasketStatus.disponible;
      }
      if (newStatus != oldStatus &&
          !FoodSaveRules.canTransitionBasket(oldStatus, newStatus)) {
        throw ApiError.conflict('Changement de statut non autorisé');
      }
      final initiale =
          (row['quantite_initiale'] as int) + math.max(0, quantite - oldQty);

      // Conditional update: guards against a concurrent reservation having
      // changed the quantity / status since we read the row.
      final changed = await txn.rawUpdate(
        'UPDATE panier SET titre = ?, contenu = ?, categorie = ?, '
        'prix_centimes = ?, prix_initial_centimes = ?, quantite = ?, '
        'quantite_initiale = ?, creneau_retrait_debut = ?, '
        'creneau_retrait_fin = ?, date_expiration = ?, statut = ?, '
        'mis_a_jour_le = ? '
        'WHERE id = ? AND commercant_id = ? AND quantite = ? AND statut = ?',
        [
          titre,
          contenu,
          categorie.apiValue,
          prix,
          prixInitial,
          quantite,
          initiale,
          isoUtc(debut),
          isoUtc(fin),
          isoUtc(expiration),
          newStatus.apiValue,
          ctx.nowIso(),
          basketId,
          merchantId,
          oldQty,
          oldStatus.apiValue,
        ],
      );
      if (changed != 1) {
        throw ApiError.conflict(
            'Le panier vient d\'être modifié par une réservation, réessayez');
      }
      await ctx.journal.log('panier_modifie',
          utilisateurId: merchantId,
          panierId: basketId,
          details: {
            'champs': body.keys.toList(),
            'quantite': quantite,
            'statut': newStatus.apiValue,
          },
          executor: txn);
      republished = oldStatus == BasketStatus.epuise &&
          newStatus == BasketStatus.disponible;
    });
    if (republished) await _notifyNearby(basketId);
    return getMine(merchantId, basketId);
  }

  // ---------------------------------------------------------------- cancel

  /// Cancels the basket, then every active reservation (refunds handled by
  /// the reservation service).
  Future<BasketDto> cancel(int merchantId, int basketId) async {
    await ctx.db.transaction((txn) async {
      final row = await _ownRow(txn, merchantId, basketId);
      final status = BasketStatus.parse(row['statut'] as String);
      if (!FoodSaveRules.canTransitionBasket(status, BasketStatus.annule)) {
        throw ApiError.conflict(
            'Ce panier est déjà clôturé (${status.label.toLowerCase()})');
      }
      final changed = await txn.rawUpdate(
        "UPDATE panier SET statut = 'annule', mis_a_jour_le = ? "
        'WHERE id = ? AND statut IN $_openStatuses',
        [ctx.nowIso(), basketId],
      );
      if (changed != 1) throw ApiError.conflict('Ce panier est déjà clôturé');
      await ctx.journal.log('panier_annule',
          utilisateurId: merchantId, panierId: basketId, executor: txn);
    });

    try {
      final cancelled = await FoodSaveReservationService(ctx)
          .cancelActiveForBasket(basketId, merchantId: merchantId);
      if (cancelled > 0) {
        await ctx.journal.log('reservations_annulees_par_commercant',
            utilisateurId: merchantId,
            panierId: basketId,
            details: {'nombre': cancelled});
      }
    } catch (e, st) {
      // The basket is cancelled either way; the operator must follow up.
      developer.log('cancelActiveForBasket failed',
          error: e, stackTrace: st, name: 'foodsave');
      await ctx.journal.log('annulation_reservations_a_traiter',
          utilisateurId: merchantId,
          panierId: basketId,
          details: {'erreur': e.toString()});
    }
    return getMine(merchantId, basketId);
  }

  // ---------------------------------------------------------------- delete

  /// Hard delete, only for baskets that never had any reservation.
  Future<void> delete(int merchantId, int basketId) async {
    final image = await ctx.db.transaction((txn) async {
      final row = await _ownRow(txn, merchantId, basketId);
      final count = (await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM reservation WHERE panier_id = ?',
        [basketId],
      ))
          .first['c'] as int;
      if (count > 0) {
        throw ApiError.conflict('Annulez le panier : il a des réservations');
      }
      await txn.delete('panier', where: 'id = ?', whereArgs: [basketId]);
      await ctx.journal.log('panier_supprime',
          utilisateurId: merchantId,
          panierId: basketId,
          details: {'titre': row['titre']},
          executor: txn);
      return row['image'] as String?;
    });
    await images.delete(image);
  }

  // ----------------------------------------------------------------- image

  /// Replaces the basket photo (JPEG/PNG, ≤ 2 MB, magic bytes checked).
  Future<BasketDto> setImage(int merchantId, int basketId,
      {required String? contentType, required Uint8List bytes}) async {
    final row = await _ownRow(ctx.db, merchantId, basketId);
    final status = BasketStatus.parse(row['statut'] as String);
    if (!FoodSaveRules.isBasketEditable(status)) {
      throw ApiError.conflict(
          'Ce panier est clôturé : sa photo ne peut plus être modifiée');
    }
    final extension = BasketImageStore.validate(contentType, bytes);
    final name = await images.save(bytes, extension);
    try {
      await ctx.db.update(
        'panier',
        {'image': name, 'mis_a_jour_le': ctx.nowIso()},
        where: 'id = ? AND commercant_id = ?',
        whereArgs: [basketId, merchantId],
      );
    } catch (_) {
      await images.delete(name);
      rethrow;
    }
    await images.delete(row['image'] as String?);
    await ctx.journal.log('image_panier_modifiee',
        utilisateurId: merchantId, panierId: basketId);
    return getMine(merchantId, basketId);
  }

  // ------------------------------------------------------------------- job

  /// Background job: baskets past `date_expiration` → `expire`.
  /// Returns the number of baskets expired.
  Future<int> expireOutdatedBaskets() async {
    final now = ctx.nowIso();
    final rows = await ctx.db.rawQuery(
      'SELECT id, commercant_id FROM panier '
      'WHERE statut IN $_openStatuses AND date_expiration <= ?',
      [now],
    );
    var expired = 0;
    for (final row in rows) {
      final id = row['id'] as int;
      final changed = await ctx.db.rawUpdate(
        "UPDATE panier SET statut = 'expire', mis_a_jour_le = ? "
        'WHERE id = ? AND statut IN $_openStatuses AND date_expiration <= ?',
        [now, id, now],
      );
      if (changed == 1) {
        expired++;
        await ctx.journal.log('panier_expire',
            utilisateurId: row['commercant_id'] as int, panierId: id);
      }
    }
    return expired;
  }

  // --------------------------------------------------------------- helpers

  static ApiError _notFound() => ApiError.notFound('Panier introuvable');

  Future<Map<String, Object?>> _ownRow(
      DatabaseExecutor executor, int merchantId, int basketId) async {
    final rows = await executor.query('panier',
        where: 'id = ? AND commercant_id = ?',
        whereArgs: [basketId, merchantId],
        limit: 1);
    if (rows.isEmpty) throw _notFound();
    return rows.first;
  }

  void _validate({
    required String titre,
    required String contenu,
    required int prix,
    required int prixInitial,
    required int quantite,
    required DateTime debut,
    required DateTime fin,
    required DateTime expiration,
  }) {
    final error = FoodSaveRules.basketError(
      title: titre,
      content: contenu,
      priceCents: prix,
      initialPriceCents: prixInitial,
      quantity: quantite,
      pickupStart: debut,
      pickupEnd: fin,
      expiry: expiration,
    );
    if (error != null) throw ApiError.badRequest(error);
  }

  void _requireFutureEnd(DateTime fin) {
    if (!fin.isAfter(ctx.now())) {
      throw ApiError.badRequest(
          'La fin du créneau de retrait doit être dans le futur');
    }
  }

  /// Notification failures never break the merchant's operation.
  Future<int> _notifyNearby(int basketId) async {
    try {
      return await FoodSaveNearbyNotificationService(ctx)
          .notifyNearbyClients(basketId);
    } catch (e, st) {
      developer.log('notifyNearbyClients failed',
          error: e, stackTrace: st, name: 'foodsave');
      return 0;
    }
  }
}
