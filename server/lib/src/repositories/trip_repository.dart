import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `trajet`. Rows are always read joined with the driver
/// (`utilisateur`) and the vehicle, so [toDto] has everything it needs.
class TripRepository {
  TripRepository(this._db);

  final Database _db;

  /// Base SELECT reused by every read query (and by the proximity search).
  static const String selectSql = '''
SELECT t.*,
       u.prenom AS c_prenom, u.nom AS c_nom, u.photo AS c_photo,
       v.marque AS v_marque, v.modele AS v_modele,
       v.couleur AS v_couleur, v.nb_places AS v_nb_places
FROM trajet t
JOIN utilisateur u ON u.id = t.conducteur_id
JOIN vehicule v ON v.id = t.vehicule_id
''';

  Future<Map<String, Object?>?> findById(int id) async {
    final rows = await _db.rawQuery('$selectSql WHERE t.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listForDriver(int conducteurId) =>
      _db.rawQuery(
        '$selectSql WHERE t.conducteur_id = ? ORDER BY t.date_heure_depart DESC',
        [conducteurId],
      );

  /// Open trips that could match a proximity search: a cheap SQL pre-filter
  /// (bounding box around the departure + filters). The exact distance is then
  /// checked in Dart with the Haversine formula (see `TripService.search`).
  Future<List<Map<String, Object?>>> searchCandidates({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required String fromIso,
    String? toIso,
    required int minSeats,
    required int excludeDriverId,
    int? maxPriceCentimes,
    String? ambiance,
    bool nonFumeur = false,
    bool animaux = false,
    bool femmes = false,
    bool includeWomenOnly = false,
  }) {
    final where = <String>[
      "t.statut = 'ouvert'",
      't.places_disponibles >= ?',
      't.date_heure_depart > ?',
      't.depart_latitude BETWEEN ? AND ?',
      't.depart_longitude BETWEEN ? AND ?',
      't.conducteur_id != ?',
    ];
    final args = <Object?>[
      minSeats,
      fromIso,
      minLat,
      maxLat,
      minLng,
      maxLng,
      excludeDriverId,
    ];
    if (toIso != null) {
      where.add('t.date_heure_depart < ?');
      args.add(toIso);
    }
    if (maxPriceCentimes != null) {
      where.add('t.prix_par_place_centimes <= ?');
      args.add(maxPriceCentimes);
    }
    if (ambiance != null) {
      where.add('t.ambiance = ?');
      args.add(ambiance);
    }
    if (nonFumeur) where.add('t.fumeur_accepte = 0');
    if (animaux) where.add('t.animaux_acceptes = 1');
    if (femmes) where.add('t.reserve_aux_femmes = 1');
    if (!includeWomenOnly) where.add('t.reserve_aux_femmes = 0');
    return _db.rawQuery(
      '$selectSql WHERE ${where.join(' AND ')} '
      'ORDER BY t.date_heure_depart ASC LIMIT 200',
      args,
    );
  }

  /// True when the driver already has an active trip leaving at [dateIso].
  Future<bool> driverHasActiveTripAt(int conducteurId, String dateIso) async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM trajet WHERE conducteur_id = ? "
      "AND date_heure_depart = ? AND statut IN ('ouvert', 'complet')",
      [conducteurId, dateIso],
    );
    return (rows.first['c'] as int) > 0;
  }

  Future<int> insert({
    required int conducteurId,
    required int vehiculeId,
    required String departAdresse,
    required double departLatitude,
    required double departLongitude,
    required String arriveeAdresse,
    required double arriveeLatitude,
    required double arriveeLongitude,
    required String dateHeureDepartIso,
    required int places,
    required int prixParPlaceCentimes,
    required Ambiance ambiance,
    required bool fumeurAccepte,
    required bool animauxAcceptes,
    required bool reserveAuxFemmes,
  }) =>
      _db.insert('trajet', {
        'conducteur_id': conducteurId,
        'vehicule_id': vehiculeId,
        'depart_adresse': departAdresse,
        'depart_latitude': departLatitude,
        'depart_longitude': departLongitude,
        'arrivee_adresse': arriveeAdresse,
        'arrivee_latitude': arriveeLatitude,
        'arrivee_longitude': arriveeLongitude,
        'date_heure_depart': dateHeureDepartIso,
        'places_disponibles': places,
        'places_totales': places,
        'prix_par_place_centimes': prixParPlaceCentimes,
        'devise': 'TND',
        'statut': TripStatus.ouvert.apiValue,
        'ambiance': ambiance.apiValue,
        'fumeur_accepte': fumeurAccepte ? 1 : 0,
        'animaux_acceptes': animauxAcceptes ? 1 : 0,
        'reserve_aux_femmes': reserveAuxFemmes ? 1 : 0,
        'cree_le': DateTime.now().toIso8601String(),
      });

  /// Maps a joined row to the public DTO. The driver is shown as "Prénom N."
  /// (privacy). Rating fields stay empty until the reviews module exists.
  TripDto toDto(
    Map<String, Object?> row, {
    double? distanceDepartKm,
    double? distanceArriveeKm,
    int? scoreMatching,
    int? ecartHeureMin,
  }) {
    final nom = row['c_nom'] as String;
    final initiale = nom.isEmpty ? '' : ' ${nom.substring(0, 1).toUpperCase()}.';
    return TripDto(
      id: row['id'] as int,
      conducteurId: row['conducteur_id'] as int,
      conducteurNom: '${row['c_prenom']}$initiale',
      conducteurPhoto: row['c_photo'] as String?,
      vehicule: VehicleDto(
        id: row['vehicule_id'] as int,
        marque: row['v_marque'] as String,
        modele: row['v_modele'] as String,
        couleur: row['v_couleur'] as String,
        nbPlaces: row['v_nb_places'] as int,
      ),
      departAdresse: row['depart_adresse'] as String,
      departLatitude: (row['depart_latitude'] as num).toDouble(),
      departLongitude: (row['depart_longitude'] as num).toDouble(),
      arriveeAdresse: row['arrivee_adresse'] as String,
      arriveeLatitude: (row['arrivee_latitude'] as num).toDouble(),
      arriveeLongitude: (row['arrivee_longitude'] as num).toDouble(),
      dateHeureDepartIso: row['date_heure_depart'] as String,
      placesDisponibles: row['places_disponibles'] as int,
      placesTotales: row['places_totales'] as int,
      prixParPlaceCentimes: row['prix_par_place_centimes'] as int,
      devise: row['devise'] as String,
      statut: TripStatus.parse(row['statut'] as String),
      motifAnnulation: row['motif_annulation'] as String?,
      ambiance: Ambiance.parse(row['ambiance'] as String),
      fumeurAccepte: (row['fumeur_accepte'] as int) == 1,
      animauxAcceptes: (row['animaux_acceptes'] as int) == 1,
      reserveAuxFemmes: (row['reserve_aux_femmes'] as int) == 1,
      distanceDepartKm: distanceDepartKm,
      distanceArriveeKm: distanceArriveeKm,
      scoreMatching: scoreMatching,
      ecartHeureMin: ecartHeureMin,
    );
  }
}
