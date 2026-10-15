import 'package:proxilife_shared/proxilife_shared.dart';

import '../foodsave_context.dart';

/// Merchant dashboard aggregates.
class FoodSaveStatsService {
  FoodSaveStatsService(this.ctx);

  final FoodSaveContext ctx;

  static const int days = 7;

  Future<MerchantStatsDto> forMerchant(int merchantId) async {
    final db = ctx.db;

    final activeBaskets = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM panier '
      "WHERE commercant_id = ? AND statut IN ('disponible', 'epuise')",
      [merchantId],
    ))
        .first['c'] as int;

    final byStatusRows = await db.rawQuery(
      'SELECT r.statut AS statut, COUNT(*) AS c, '
      'COALESCE(SUM(r.quantite_reservee), 0) AS q '
      'FROM reservation r JOIN panier p ON p.id = r.panier_id '
      'WHERE p.commercant_id = ? GROUP BY r.statut',
      [merchantId],
    );
    final byStatus = {for (final s in ReservationStatus.values) s.apiValue: 0};
    var mealsSaved = 0;
    for (final row in byStatusRows) {
      final statut = row['statut'] as String;
      byStatus[statut] = row['c'] as int;
      if (statut == ReservationStatus.retire.apiValue) {
        mealsSaved = (row['q'] as num).toInt();
      }
    }

    final revenue = (await db.rawQuery(
      'SELECT COALESCE(SUM(r.montant_centimes), 0) AS s '
      'FROM reservation r JOIN panier p ON p.id = r.panier_id '
      "WHERE p.commercant_id = ? AND r.statut_paiement = 'paye' "
      "AND r.statut != 'annule'",
      [merchantId],
    ))
        .first['s'] as num;

    final pickedUp = byStatus[ReservationStatus.retire.apiValue]!;
    final expired = byStatus[ReservationStatus.expire.apiValue]!;
    final pickupRate = pickedUp + expired == 0
        ? 0
        : (pickedUp * 100 / (pickedUp + expired)).round();

    return MerchantStatsDto(
      paniersActifs: activeBaskets,
      reservationsEnAttente: byStatus[ReservationStatus.enAttente.apiValue]!,
      retraitsTotal: pickedUp,
      repasSauves: mealsSaved,
      revenusCentimes: revenue.toInt(),
      tauxRetrait: pickupRate,
      parJour: await _lastDays(merchantId),
      parStatut: byStatus,
    );
  }

  /// Exactly [days] UTC days ending today, oldest first, zeros filled.
  Future<List<DailyStatDto>> _lastDays(int merchantId) async {
    final now = ctx.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final keys = [
      for (var i = days - 1; i >= 0; i--)
        _dayKey(today.subtract(Duration(days: i))),
    ];
    final from = '${keys.first}T00:00:00.000Z';

    final created = await ctx.db.rawQuery(
      'SELECT substr(r.date, 1, 10) AS d, COUNT(*) AS c, '
      "COALESCE(SUM(CASE WHEN r.statut_paiement = 'paye' "
      "AND r.statut != 'annule' THEN r.montant_centimes ELSE 0 END), 0) AS s "
      'FROM reservation r JOIN panier p ON p.id = r.panier_id '
      'WHERE p.commercant_id = ? AND r.date >= ? GROUP BY d',
      [merchantId, from],
    );
    final pickups = await ctx.db.rawQuery(
      'SELECT substr(r.retire_le, 1, 10) AS d, COUNT(*) AS c '
      'FROM reservation r JOIN panier p ON p.id = r.panier_id '
      "WHERE p.commercant_id = ? AND r.statut = 'retire' "
      'AND r.retire_le >= ? GROUP BY d',
      [merchantId, from],
    );
    final reservationsByDay = <String, int>{};
    final revenueByDay = <String, int>{};
    for (final row in created) {
      final d = row['d'] as String;
      reservationsByDay[d] = row['c'] as int;
      revenueByDay[d] = (row['s'] as num).toInt();
    }
    final pickupsByDay = {
      for (final row in pickups) row['d'] as String: row['c'] as int,
    };
    return [
      for (final k in keys)
        DailyStatDto(
          date: k,
          reservations: reservationsByDay[k] ?? 0,
          retraits: pickupsByDay[k] ?? 0,
          revenusCentimes: revenueByDay[k] ?? 0,
        ),
    ];
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
