import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite/sqflite.dart';

import 'reservation_cache.dart';

/// [FoodSaveReservationCache] in a local SQLite database on the phone
/// (package `sqflite`). Opened lazily on first use, so building a screen
/// never waits for the disk.
class SqfliteReservationCache implements FoodSaveReservationCache {
  /// [factory] and [path] are injected by tests (`sqflite_common_ffi`, in
  /// memory); the app uses the device defaults.
  SqfliteReservationCache({this._factory, this._path});

  /// One store for the whole app (one open database).
  static final SqfliteReservationCache shared = SqfliteReservationCache();

  static const String table = 'foodsave_reservation_locale';
  static const int schemaVersion = 1;

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _db;

  Future<Database> get database => _db ??= _open();

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path =
        _path ?? p.join(await factory.getDatabasesPath(), 'foodsave_local.db');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          // A few real columns (to sort and filter in SQL) plus the whole
          // reservation as JSON (basket and store included) to rebuild it.
          await db.execute('''
            CREATE TABLE $table (
              utilisateur_id INTEGER NOT NULL,
              id INTEGER NOT NULL,
              date TEXT NOT NULL,
              statut TEXT NOT NULL,
              montant_centimes INTEGER NOT NULL,
              date_expiration_qr TEXT,
              qr_token TEXT,
              donnees_json TEXT NOT NULL,
              enregistre_le TEXT NOT NULL,
              PRIMARY KEY (utilisateur_id, id)
            )''');
          await db.execute(
            'CREATE INDEX idx_${table}_date ON $table (utilisateur_id, date DESC)',
          );
        },
      ),
    );
  }

  Map<String, Object?> _row(int userId, ReservationDto r) => {
    'utilisateur_id': userId,
    'id': r.id,
    'date': r.date.toUtc().toIso8601String(),
    'statut': r.statut.apiValue,
    'montant_centimes': r.montantCentimes,
    'date_expiration_qr': r.dateExpirationQr?.toUtc().toIso8601String(),
    'qr_token': r.qrToken,
    'donnees_json': jsonEncode(r.toJson()),
    'enregistre_le': DateTime.now().toUtc().toIso8601String(),
  };

  static ReservationDto _fromRow(Map<String, Object?> row) =>
      ReservationDto.fromJson(
        jsonDecode(row['donnees_json'] as String) as Map<String, dynamic>,
      );

  @override
  Future<void> replaceAll(int userId, List<ReservationDto> list) async {
    final db = await database;
    // One transaction: the list is never seen half replaced.
    await db.transaction((txn) async {
      await txn.delete(table, where: 'utilisateur_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final r in list) {
        batch.insert(table, _row(userId, r));
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> save(int userId, ReservationDto reservation) async {
    final db = await database;
    await db.insert(
      table,
      _row(userId, reservation),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ReservationDto>> all(int userId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'utilisateur_id = ?',
      whereArgs: [userId],
      orderBy: 'date DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<ReservationDto?> byId(int userId, int id) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'utilisateur_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}
