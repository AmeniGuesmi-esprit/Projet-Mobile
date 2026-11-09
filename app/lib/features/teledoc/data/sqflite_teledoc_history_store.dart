import 'package:path/path.dart' as p;
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/teledoc_history_store.dart';

/// [TeledocHistoryStore] in a local SQLite database (package `sqflite`).
///
/// The database is opened lazily on first use, so building a screen never
/// waits for the disk.
class SqfliteTeledocHistoryStore implements TeledocHistoryStore {
  /// [factory] and [path] are injected by tests (`sqflite_common_ffi`, in
  /// memory); the app uses the device defaults.
  SqfliteTeledocHistoryStore({this._factory, this._path});

  /// One store for the whole app (one open database).
  static final SqfliteTeledocHistoryStore shared = SqfliteTeledocHistoryStore();

  static const String table = 'teledoc_consultation_locale';
  static const int schemaVersion = 1;

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _db;

  Future<Database> get database => _db ??= _open();

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path =
        _path ?? p.join(await factory.getDatabasesPath(), 'teledoc_local.db');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          // Columns use the API's JSON names so a row maps straight back to
          // TeledocConsultationDto.fromJson. No salle_appel column on purpose.
          await db.execute('''
            CREATE TABLE $table (
              utilisateur_id INTEGER NOT NULL,
              id INTEGER NOT NULL,
              date_debut TEXT NOT NULL,
              date_fin TEXT,
              type TEXT NOT NULL CHECK (type IN ('audio', 'video')),
              ordonnance TEXT,
              id_pharmacie INTEGER,
              pharmacie_nom TEXT,
              id_demande INTEGER NOT NULL,
              id_medecin INTEGER,
              medecin_nom TEXT,
              patient_nom TEXT,
              motif TEXT NOT NULL,
              urgence TEXT NOT NULL,
              statut_demande TEXT NOT NULL,
              enregistre_le TEXT NOT NULL,
              PRIMARY KEY (utilisateur_id, id)
            )''');
          await db.execute(
            'CREATE INDEX idx_${table}_date '
            'ON $table (utilisateur_id, date_debut DESC)',
          );
        },
      ),
    );
  }

  Map<String, Object?> _row(int userId, TeledocConsultationDto c) => {
        ...c.toJson()..remove('salle_appel'),
        'utilisateur_id': userId,
        'enregistre_le': DateTime.now().toIso8601String(),
      };

  static TeledocConsultationDto _fromRow(Map<String, Object?> row) =>
      TeledocConsultationDto.fromJson(Map<String, dynamic>.of(row));

  @override
  Future<void> replaceAll(
    int userId,
    List<TeledocConsultationDto> list,
  ) async {
    final db = await database;
    // One transaction: the history is never seen half replaced.
    await db.transaction((txn) async {
      await txn.delete(table, where: 'utilisateur_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final c in list) {
        batch.insert(table, _row(userId, c));
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> save(int userId, TeledocConsultationDto consultation) async {
    final db = await database;
    await db.insert(
      table,
      _row(userId, consultation),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<TeledocConsultationDto>> all(int userId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'utilisateur_id = ?',
      whereArgs: [userId],
      orderBy: 'date_debut DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<TeledocConsultationDto?> byId(int userId, int id) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'utilisateur_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> delete(int userId, int id) async {
    final db = await database;
    await db.delete(
      table,
      where: 'utilisateur_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}
