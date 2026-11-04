import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `teledoc_pharmacie`.
class TeledocPharmacyRepository {
  TeledocPharmacyRepository(this._db);

  final Database _db;

  Future<List<Map<String, Object?>>> listOnDuty() =>
      _db.query('teledoc_pharmacie', where: 'de_garde = 1');

  Future<Map<String, Object?>?> findById(int id) async {
    final rows =
        await _db.query('teledoc_pharmacie', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  TeledocPharmacyDto toDto(Map<String, Object?> row, {double? distanceKm}) =>
      TeledocPharmacyDto(
        id: row['id'] as int,
        nom: row['nom'] as String,
        adresse: row['adresse'] as String,
        telephone: row['telephone'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        deGarde: (row['de_garde'] as int) == 1,
        distanceKm: distanceKm,
      );
}
