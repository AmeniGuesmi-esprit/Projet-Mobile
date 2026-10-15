import 'package:proxilife_shared/proxilife_shared.dart';

import '../../api_error.dart';
import '../foodsave_context.dart';

/// Last known client position (opt-in) + the caller's in-app FoodSave
/// notifications. Every method is scoped to [userId]: a user never reads or
/// changes another user's rows.
class FoodSaveGeoService {
  FoodSaveGeoService(this.ctx);

  final FoodSaveContext ctx;

  /// Maximum number of notifications returned by [listNotifications].
  static const int notificationsPageSize = 100;

  // ------------------------------------------------------------- location

  /// Parses and validates a `{latitude, longitude}` body.
  static (double, double) parseLatLng(Map<String, dynamic> body) {
    final lat = body['latitude'];
    final lng = body['longitude'];
    if (lat is! num || lng is! num) {
      throw ApiError.badRequest('Latitude et longitude sont obligatoires');
    }
    final latitude = lat.toDouble();
    final longitude = lng.toDouble();
    if (!isValidLatLng(latitude, longitude)) {
      throw ApiError.badRequest('Coordonnées GPS invalides');
    }
    return (latitude, longitude);
  }

  /// Upserts the client's position (one row per user).
  Future<void> saveLocation(int userId, double latitude, double longitude) async {
    if (!isValidLatLng(latitude, longitude)) {
      throw ApiError.badRequest('Coordonnées GPS invalides');
    }
    await ctx.db.rawInsert(
      'INSERT INTO localisation_client '
      '(utilisateur_id, latitude, longitude, mis_a_jour_le) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(utilisateur_id) DO UPDATE SET latitude = excluded.latitude, '
      'longitude = excluded.longitude, mis_a_jour_le = excluded.mis_a_jour_le',
      [userId, latitude, longitude, ctx.nowIso()],
    );
  }

  /// Forgets the position (the client refused / revoked geolocation).
  Future<void> clearLocation(int userId) async {
    await ctx.db.delete('localisation_client',
        where: 'utilisateur_id = ?', whereArgs: [userId]);
  }

  /// `{latitude, longitude, mis_a_jour_le}` or null when none is stored.
  Future<Map<String, Object?>?> getLocation(int userId) async {
    final rows = await ctx.db.query(
      'localisation_client',
      columns: ['latitude', 'longitude', 'mis_a_jour_le'],
      where: 'utilisateur_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'latitude': (row['latitude'] as num).toDouble(),
      'longitude': (row['longitude'] as num).toDouble(),
      'mis_a_jour_le': row['mis_a_jour_le'],
    };
  }

  // -------------------------------------------------------- notifications

  /// Own notifications, newest first, at most [notificationsPageSize].
  Future<List<FoodSaveNotificationDto>> listNotifications(int userId,
      {bool unreadOnly = false}) async {
    final rows = await ctx.db.query(
      'foodsave_notification',
      where: unreadOnly
          ? 'utilisateur_id = ? AND lu = 0'
          : 'utilisateur_id = ?',
      whereArgs: [userId],
      orderBy: 'cree_le DESC, id DESC',
      limit: notificationsPageSize,
    );
    return rows.map(notificationFromRow).toList();
  }

  /// Marks one own notification as read. 404 when it does not exist or
  /// belongs to someone else (no information leak).
  Future<void> markRead(int userId, int notificationId) async {
    final count = await ctx.db.update(
      'foodsave_notification',
      {'lu': 1},
      where: 'id = ? AND utilisateur_id = ?',
      whereArgs: [notificationId, userId],
    );
    if (count == 0) throw ApiError.notFound('Notification introuvable');
  }

  /// Marks every own unread notification as read. Returns how many changed.
  Future<int> markAllRead(int userId) => ctx.db.update(
        'foodsave_notification',
        {'lu': 1},
        where: 'utilisateur_id = ? AND lu = 0',
        whereArgs: [userId],
      );
}

/// `foodsave_notification` row -> DTO.
FoodSaveNotificationDto notificationFromRow(Map<String, Object?> row) =>
    FoodSaveNotificationDto(
      id: row['id'] as int,
      type: FoodSaveNotificationType.parse(row['type'] as String),
      titre: row['titre'] as String,
      message: row['message'] as String,
      panierId: row['panier_id'] as int?,
      reservationId: row['reservation_id'] as int?,
      lu: (row['lu'] as int) != 0,
      creeLe: DateTime.parse(row['cree_le'] as String),
    );
