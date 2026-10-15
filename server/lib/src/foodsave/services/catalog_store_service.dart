import 'package:proxilife_shared/proxilife_shared.dart';

import '../../api_error.dart';
import '../foodsave_context.dart';
import '../foodsave_mappers.dart';
import 'catalog_input.dart';

/// The merchant's store (one per merchant, with its GPS position).
class FoodSaveStoreService {
  FoodSaveStoreService(this.ctx);

  final FoodSaveContext ctx;

  Future<StoreDto?> findByMerchant(int merchantId) async {
    final rows = await ctx.db.query('commerce',
        where: 'commercant_id = ?', whereArgs: [merchantId], limit: 1);
    return rows.isEmpty ? null : storeFromRow(rows.first);
  }

  Future<StoreDto> getMine(int merchantId) async =>
      await findByMerchant(merchantId) ??
      (throw ApiError.notFound('Commerce non configuré'));

  /// Creates or updates the merchant's store from a JSON body.
  Future<StoreDto> upsert(int merchantId, Map<String, dynamic> body) async {
    final nom = reqString(body, 'nom');
    if (nom.length < 2 || nom.length > 80) {
      throw ApiError.badRequest(
          'Le nom du commerce doit contenir entre 2 et 80 caractères');
    }
    final adresse = reqString(body, 'adresse');
    if (adresse.length < 3 || adresse.length > 200) {
      throw ApiError.badRequest(
          'L\'adresse doit contenir entre 3 et 200 caractères');
    }
    final latitude = reqDouble(body, 'latitude');
    final longitude = reqDouble(body, 'longitude');
    if (!isValidLatLng(latitude, longitude)) {
      throw ApiError.badRequest('Coordonnées GPS invalides');
    }
    final categorie = reqCategory(body, 'categorie');

    final now = ctx.nowIso();
    final values = {
      'nom': nom,
      'adresse': adresse,
      'latitude': latitude,
      'longitude': longitude,
      'categorie': categorie.apiValue,
      'mis_a_jour_le': now,
    };
    final existing = await findByMerchant(merchantId);
    if (existing == null) {
      await ctx.db.insert('commerce', {
        ...values,
        'commercant_id': merchantId,
        'cree_le': now,
      });
      await ctx.journal.log('commerce_cree', utilisateurId: merchantId);
    } else {
      await ctx.db.update('commerce', values,
          where: 'id = ?', whereArgs: [existing.id]);
      await ctx.journal.log('commerce_modifie', utilisateurId: merchantId);
    }
    return getMine(merchantId);
  }
}
