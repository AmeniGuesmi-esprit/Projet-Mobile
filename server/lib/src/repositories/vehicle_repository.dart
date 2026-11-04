import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `vehicule`.
class VehicleRepository {
  VehicleRepository(this._db);

  final Database _db;

  Future<List<Map<String, Object?>>> listForUser(int utilisateurId) =>
      _db.query('vehicule',
          where: 'utilisateur_id = ?',
          whereArgs: [utilisateurId],
          orderBy: 'id DESC');

  Future<Map<String, Object?>?> findById(int id) async {
    final rows = await _db.query('vehicule', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> countForUser(int utilisateurId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM vehicule WHERE utilisateur_id = ?',
      [utilisateurId],
    );
    return rows.first['c'] as int;
  }

  Future<int> insert({
    required int utilisateurId,
    required String marque,
    required String modele,
    required String couleur,
    required int nbPlaces,
  }) =>
      _db.insert('vehicule', {
        'marque': marque,
        'modele': modele,
        'couleur': couleur,
        'nb_places': nbPlaces,
        'utilisateur_id': utilisateurId,
        'cree_le': DateTime.now().toIso8601String(),
      });

  /// True when at least one trip (any status) references this vehicle.
  Future<bool> hasTrips(int vehiculeId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM trajet WHERE vehicule_id = ?',
      [vehiculeId],
    );
    return (rows.first['c'] as int) > 0;
  }

  Future<void> delete(int id) =>
      _db.delete('vehicule', where: 'id = ?', whereArgs: [id]);

  VehicleDto toDto(Map<String, Object?> row) => VehicleDto(
        id: row['id'] as int,
        marque: row['marque'] as String,
        modele: row['modele'] as String,
        couleur: row['couleur'] as String,
        nbPlaces: row['nb_places'] as int,
      );
}
