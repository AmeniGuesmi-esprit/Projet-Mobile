import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL access for `demande_service` and `intervention`. Methods that take a
/// [DatabaseExecutor] are meant to run inside a transaction.
class ServiceNowRepository {
  ServiceNowRepository(this._db);

  final Database _db;

  /// One row per request, with its client, its latest intervention, the
  /// prestataire and the payment status (`i_`, `p_`, `t_` column prefixes).
  static const String _select = '''
SELECT d.*,
  c.prenom AS client_prenom, c.nom AS client_nom,
  c.telephone AS client_telephone,
  i.id AS i_id, i.prestataire_id AS i_prestataire_id,
  i.date_prevue AS i_date_prevue, i.date_debut AS i_date_debut,
  i.date_fin AS i_date_fin, i.rapport AS i_rapport,
  i.prix_centimes AS i_prix_centimes, i.statut AS i_statut,
  i.transaction_id AS i_transaction_id,
  i.qr_code AS i_qr_code, i.en_route_le AS i_en_route_le,
  i.prestataire_lat AS i_prestataire_lat,
  i.prestataire_lng AS i_prestataire_lng,
  i.position_le AS i_position_le,
  i.photo_avant AS i_photo_avant, i.photo_apres AS i_photo_apres,
  i.note AS i_note, i.commentaire AS i_commentaire,
  (SELECT AVG(n.note) FROM intervention n
    WHERE n.prestataire_id = i.prestataire_id) AS p_note_moyenne,
  (SELECT COUNT(n.note) FROM intervention n
    WHERE n.prestataire_id = i.prestataire_id) AS p_nb_notes,
  p.prenom AS p_prenom, p.nom AS p_nom, p.telephone AS p_telephone,
  p.email AS p_email,
  t.statut AS t_statut
FROM demande_service d
JOIN utilisateur c ON c.id = d.client_id
LEFT JOIN intervention i ON i.id = (
  SELECT MAX(x.id) FROM intervention x WHERE x.demande_id = d.id
)
LEFT JOIN utilisateur p ON p.id = i.prestataire_id
LEFT JOIN transaction_ t ON t.id = i.transaction_id
''';

  Future<Map<String, Object?>?> findDemande(int id) async {
    final rows = await _db.rawQuery('$_select WHERE d.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Only the latest intervention of a request can be found this way.
  Future<Map<String, Object?>?> findByIntervention(int interventionId) async {
    final rows =
        await _db.rawQuery('$_select WHERE i.id = ?', [interventionId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// A client's requests, newest first.
  Future<List<Map<String, Object?>>> listForClient(int clientId) => _db.rawQuery(
        '$_select WHERE d.client_id = ? ORDER BY d.id DESC',
        [clientId],
      );

  /// Requests waiting for a prestataire, the most pressing first.
  Future<List<Map<String, Object?>>> listOpen({ServiceNowType? type}) =>
      _db.rawQuery(
        "$_select WHERE d.statut = 'en_attente' "
        '${type == null ? '' : 'AND d.type = ? '}'
        'ORDER BY d.date_souhaitee ASC, d.id ASC',
        [if (type != null) type.apiValue],
      );

  /// Requests whose latest intervention belongs to this prestataire: live
  /// ones first, then by planned date.
  Future<List<Map<String, Object?>>> listForPrestataire(int prestataireId) =>
      _db.rawQuery('''
$_select
WHERE i.prestataire_id = ? AND d.statut <> 'en_attente'
ORDER BY CASE i.statut
  WHEN 'en_cours' THEN 0
  WHEN 'planifiee' THEN 1
  WHEN 'terminee' THEN 2
  ELSE 3 END, i.date_prevue ASC
''', [prestataireId]);

  Future<int> insertDemande({
    required int clientId,
    required ServiceNowType type,
    required String description,
    required String adresse,
    required DateTime dateSouhaitee,
    required DateTime now,
    double? latitude,
    double? longitude,
  }) {
    final stamp = now.toUtc().toIso8601String();
    return _db.insert('demande_service', {
      'latitude': latitude,
      'longitude': longitude,
      'client_id': clientId,
      'type': type.apiValue,
      'description': description,
      'adresse': adresse,
      'date_souhaitee': dateSouhaitee.toUtc().toIso8601String(),
      'statut': DemandeServiceStatus.enAttente.apiValue,
      'cree_le': stamp,
      'modifie_le': stamp,
    });
  }

  /// Updates the request only while it is still waiting. Returns false when
  /// a prestataire took it in the meantime.
  Future<bool> updateOpenDemande(
    int id, {
    required ServiceNowType type,
    required String description,
    required String adresse,
    required DateTime dateSouhaitee,
    required DateTime now,
    required double? latitude,
    required double? longitude,
  }) async {
    final count = await _db.update(
      'demande_service',
      {
        'latitude': latitude,
        'longitude': longitude,
        'type': type.apiValue,
        'description': description,
        'adresse': adresse,
        'date_souhaitee': dateSouhaitee.toUtc().toIso8601String(),
        'modifie_le': now.toUtc().toIso8601String(),
      },
      where: 'id = ? AND statut = ?',
      whereArgs: [id, DemandeServiceStatus.enAttente.apiValue],
    );
    return count == 1;
  }

  /// Moves a request from [from] to [to]. Returns false when its status is
  /// no longer [from], which makes concurrent actions safe.
  Future<bool> moveDemande(
    DatabaseExecutor executor,
    int id, {
    required DemandeServiceStatus from,
    required DemandeServiceStatus to,
    required DateTime now,
  }) async {
    final count = await executor.update(
      'demande_service',
      {'statut': to.apiValue, 'modifie_le': now.toUtc().toIso8601String()},
      where: 'id = ? AND statut = ?',
      whereArgs: [id, from.apiValue],
    );
    return count == 1;
  }

  Future<int> insertIntervention(
    DatabaseExecutor executor, {
    required int demandeId,
    required int prestataireId,
    required DateTime datePrevue,
    required int prixCentimes,
    required String qrCode,
    required DateTime now,
  }) {
    final stamp = now.toUtc().toIso8601String();
    return executor.insert('intervention', {
      'qr_code': qrCode,
      'demande_id': demandeId,
      'prestataire_id': prestataireId,
      'date_prevue': datePrevue.toUtc().toIso8601String(),
      'prix_centimes': prixCentimes,
      'statut': InterventionStatus.planifiee.apiValue,
      'cree_le': stamp,
      'modifie_le': stamp,
    });
  }

  /// Moves an intervention from [from] to [to], applying [values] too.
  Future<bool> moveIntervention(
    DatabaseExecutor executor,
    int id, {
    required InterventionStatus from,
    required InterventionStatus to,
    required DateTime now,
    Map<String, Object?> values = const {},
  }) async {
    final count = await executor.update(
      'intervention',
      {
        ...values,
        'statut': to.apiValue,
        'modifie_le': now.toUtc().toIso8601String(),
      },
      where: 'id = ? AND statut = ?',
      whereArgs: [id, from.apiValue],
    );
    return count == 1;
  }

  /// Plain field update, for changes that are not status moves.
  Future<void> updateIntervention(
    int id,
    Map<String, Object?> values, {
    required DateTime now,
  }) async {
    await _db.update(
      'intervention',
      {...values, 'modifie_le': now.toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Saves the rating unless one exists. False when already rated.
  Future<bool> rateOnce(
    int id, {
    required int note,
    required String? commentaire,
    required DateTime now,
  }) async {
    final count = await _db.update(
      'intervention',
      {
        'note': note,
        'commentaire': commentaire,
        'modifie_le': now.toUtc().toIso8601String(),
      },
      where: 'id = ? AND note IS NULL',
      whereArgs: [id],
    );
    return count == 1;
  }

  /// Latest final prices for a type of service (for the price estimate).
  Future<List<int>> pastPrices(ServiceNowType type) async {
    final rows = await _db.rawQuery('''
SELECT i.prix_centimes AS prix
FROM intervention i
JOIN demande_service d ON d.id = i.demande_id
WHERE d.type = ? AND i.statut = 'terminee'
ORDER BY i.id DESC
LIMIT 200
''', [type.apiValue]);
    return [for (final row in rows) row['prix'] as int];
  }

  Future<Map<String, Object?>?> findProfile(int userId) async {
    final rows = await _db.query(
      'prestataire_profil',
      where: 'utilisateur_id = ?',
      whereArgs: [userId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveProfile(
    int userId, {
    required String specialites,
    required double? latitude,
    required double? longitude,
    required DateTime now,
  }) async {
    await _db.rawInsert(
      'INSERT OR REPLACE INTO prestataire_profil '
      '(utilisateur_id, specialites, latitude, longitude, modifie_le) '
      'VALUES (?, ?, ?, ?, ?)',
      [userId, specialites, latitude, longitude, now.toUtc().toIso8601String()],
    );
  }

  /// Active prestataires with their profile and average rating.
  Future<List<Map<String, Object?>>> listPrestataires() => _db.rawQuery('''
SELECT u.id, u.prenom, u.nom, pr.specialites, pr.latitude, pr.longitude,
  (SELECT AVG(n.note) FROM intervention n
    WHERE n.prestataire_id = u.id) AS note_moyenne,
  (SELECT COUNT(n.note) FROM intervention n
    WHERE n.prestataire_id = u.id) AS nb_notes
FROM utilisateur u
LEFT JOIN prestataire_profil pr ON pr.utilisateur_id = u.id
WHERE u.role = 'prestataire' AND u.statut_compte = 'actif'
''');

  Future<List<Map<String, Object?>>> allSlots() =>
      _db.query('prestataire_creneau');

  Future<List<Map<String, Object?>>> allDaysOff() =>
      _db.query('prestataire_jour_off');

  /// Planned dates of the interventions that still occupy a prestataire.
  Future<List<Map<String, Object?>>> liveInterventionDates() => _db.rawQuery('''
SELECT prestataire_id, date_prevue
FROM intervention
WHERE prestataire_id IS NOT NULL AND statut IN ('planifiee', 'en_cours')
''');

  /// Replaces a prestataire's whole calendar.
  Future<void> saveCalendar(
    int userId, {
    required List<DisponibiliteSlotDto> slots,
    required Set<String> daysOff,
  }) =>
      _db.transaction((txn) async {
        await txn.delete('prestataire_creneau',
            where: 'utilisateur_id = ?', whereArgs: [userId]);
        await txn.delete('prestataire_jour_off',
            where: 'utilisateur_id = ?', whereArgs: [userId]);
        for (final slot in slots) {
          await txn.insert('prestataire_creneau', {
            'utilisateur_id': userId,
            'jour': slot.jour,
            'debut_minutes': slot.debutMinutes,
            'fin_minutes': slot.finMinutes,
          });
        }
        for (final day in daysOff) {
          await txn.insert('prestataire_jour_off', {
            'utilisateur_id': userId,
            'jour': day,
          });
        }
      });

  Future<int> insertMessage({
    required int demandeId,
    required int auteurId,
    required String contenu,
    required DateTime now,
  }) =>
      _db.insert('service_now_message', {
        'demande_id': demandeId,
        'auteur_id': auteurId,
        'contenu': contenu,
        'cree_le': now.toUtc().toIso8601String(),
      });

  /// The latest 200 messages, oldest first.
  Future<List<Map<String, Object?>>> listMessages(int demandeId) async {
    final rows = await _db.rawQuery('''
SELECT m.*, u.prenom AS auteur_prenom
FROM service_now_message m
LEFT JOIN utilisateur u ON u.id = m.auteur_id
WHERE m.demande_id = ?
ORDER BY m.id DESC
LIMIT 200
''', [demandeId]);
    return rows.reversed.toList();
  }

  Future<void> addNotification({
    required int userId,
    required int demandeId,
    required String titre,
    required String message,
    required DateTime now,
  }) async {
    await _db.insert('service_now_notification', {
      'utilisateur_id': userId,
      'demande_id': demandeId,
      'titre': titre,
      'message': message,
      'cree_le': now.toUtc().toIso8601String(),
    });
  }

  /// Returns the user's undelivered notifications and marks them delivered,
  /// in one transaction, so that each one is shown exactly once.
  Future<List<Map<String, Object?>>> takeNotifications(int userId) =>
      _db.transaction((txn) async {
        final rows = await txn.query(
          'service_now_notification',
          where: 'utilisateur_id = ? AND livree = 0',
          whereArgs: [userId],
          orderBy: 'id ASC',
          limit: 20,
        );
        for (final row in rows) {
          await txn.update(
            'service_now_notification',
            {'livree': 1},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        return rows;
      });

  Future<void> setTransaction(int interventionId, int transactionId,
      {required DateTime now}) async {
    await _db.update(
      'intervention',
      {
        'transaction_id': transactionId,
        'modifie_le': now.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [interventionId],
    );
  }
}
