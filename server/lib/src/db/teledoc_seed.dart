import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/passwords.dart';

/// Demo doctors (same demo password as the other seeded accounts).
const List<({String nom, String prenom, String email, String telephone})>
    teledocDemoDoctors = [
  (
    nom: 'Ben Salah',
    prenom: 'Sami',
    email: 'dr.bensalah@proxilife.fr',
    telephone: '98111222',
  ),
  (
    nom: 'Trabelsi',
    prenom: 'Leila',
    email: 'dr.trabelsi@proxilife.fr',
    telephone: '22333444',
  ),
  (
    nom: 'Jaziri',
    prenom: 'Karim',
    email: 'dr.jaziri@proxilife.fr',
    telephone: '55666777',
  ),
];

/// Pharmacies in Greater Tunis. Coordinates are approximate but real places
/// (district centres); names and phone numbers are fictitious.
const List<
    ({
      String nom,
      String adresse,
      String telephone,
      double latitude,
      double longitude,
      bool deGarde,
    })> teledocDemoPharmacies = [
  (
    nom: 'Pharmacie de Nuit Bourguiba',
    adresse: 'Avenue Habib Bourguiba, Tunis',
    telephone: '71 240 100',
    latitude: 36.8000,
    longitude: 10.1815,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie des Berges du Lac',
    adresse: 'Rue du Lac Windermere, Les Berges du Lac 1',
    telephone: '71 960 200',
    latitude: 36.8325,
    longitude: 10.2330,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie Ennasr',
    adresse: 'Avenue Hédi Nouira, Ennasr 2, Ariana',
    telephone: '70 820 300',
    latitude: 36.8590,
    longitude: 10.1655,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie Ariana Centre',
    adresse: 'Avenue Habib Bourguiba, Ariana',
    telephone: '71 710 400',
    latitude: 36.8625,
    longitude: 10.1956,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie de La Marsa',
    adresse: 'Avenue Habib Bourguiba, La Marsa',
    telephone: '71 740 500',
    latitude: 36.8781,
    longitude: 10.3247,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie Ben Arous',
    adresse: 'Avenue de France, Ben Arous',
    telephone: '71 380 600',
    latitude: 36.7531,
    longitude: 10.2189,
    deGarde: true,
  ),
  (
    nom: 'Pharmacie du Bardo',
    adresse: 'Avenue du 20 Mars, Le Bardo',
    telephone: '71 510 700',
    latitude: 36.8092,
    longitude: 10.1340,
    deGarde: true,
  ),
  (
    // Not on duty: checks that the search filters it out.
    nom: 'Pharmacie Bab Saadoun',
    adresse: 'Place Bab Saadoun, Tunis',
    telephone: '71 560 800',
    latitude: 36.8105,
    longitude: 10.1640,
    deGarde: false,
  ),
];

/// Seeds TeleDoc demo data. Idempotent: doctors are upserted by e-mail,
/// pharmacies and demo requests are only inserted into empty tables.
/// Returns a summary for the seed script's console output.
Future<String> seedTeledoc(Database db) async {
  final hasher = const PasswordHasher();
  final now = DateTime.now();
  final summary = StringBuffer('TeleDoc Express :\n');

  // ---- Médecins (comptes de démo ordinaires, rôle medecin) ----
  final doctorIds = <int>[];
  for (var i = 0; i < teledocDemoDoctors.length; i++) {
    final doctor = teledocDemoDoctors[i];
    final existing = await db
        .query('utilisateur', where: 'email = ?', whereArgs: [doctor.email]);
    final int id;
    if (existing.isNotEmpty) {
      id = existing.first['id'] as int;
    } else {
      // A professional role needs a valid French RIB.
      final account = (i + 1).toString().padLeft(11, '0');
      final rib = '30004'
          '00001'
          '$account'
          '${computeRibKey('30004', '00001', account)}';
      id = await db.insert('utilisateur', {
        'nom': doctor.nom,
        'prenom': doctor.prenom,
        'email': doctor.email,
        'telephone': doctor.telephone,
        'mot_de_passe_hash': hasher.hashPassword('Proxilife2026!'),
        'photo': null,
        'role': UserRole.medecin.apiValue,
        'statut_compte': AccountStatus.actif.apiValue,
        'rib': rib,
        'solde_centimes': 0,
        'cree_le': now.toIso8601String(),
      });
    }
    doctorIds.add(id);
    summary.writeln('  médecin     : #$id  ${doctor.email}');
  }

  // ---- Pharmacies ----
  final pharmacyCount = await _count(db, 'teledoc_pharmacie');
  if (pharmacyCount == 0) {
    for (final pharmacy in teledocDemoPharmacies) {
      await db.insert('teledoc_pharmacie', {
        'nom': pharmacy.nom,
        'adresse': pharmacy.adresse,
        'telephone': pharmacy.telephone,
        'latitude': pharmacy.latitude,
        'longitude': pharmacy.longitude,
        'de_garde': pharmacy.deGarde ? 1 : 0,
      });
    }
  }
  summary.writeln('  pharmacies  : ${teledocDemoPharmacies.length} '
      '(${teledocDemoPharmacies.where((p) => p.deGarde).length} de garde)');

  // ---- Demandes de démo (historique + file non vide) ----
  final requestCount = await _count(db, 'teledoc_demande');
  if (requestCount == 0) {
    Future<int?> userId(String email) async {
      final rows = await db.query('utilisateur',
          columns: ['id'], where: 'email = ?', whereArgs: [email]);
      return rows.isEmpty ? null : rows.first['id'] as int;
    }

    // Seeded requests are demo data: they were never paid (transaction_id
    // stays null).
    final client = await userId('client@proxilife.fr');
    if (client != null) {
      final start = now.subtract(const Duration(days: 1, hours: 2));
      final demandeId = await db.insert('teledoc_demande', {
        'motif': 'Mal de gorge',
        'description': 'Gorge irritée et fièvre légère depuis deux jours',
        'urgence': TeledocUrgency.faible.apiValue,
        'photo_symptome': null,
        'statut': TeledocRequestStatus.terminee.apiValue,
        'patient_id': client,
        'transaction_id': null,
        'cree_le':
            start.subtract(const Duration(minutes: 25)).toIso8601String(),
        'modifie_le': start.toIso8601String(),
      });
      final pharmacy = await db.query('teledoc_pharmacie',
          columns: ['id'], where: 'de_garde = 1', orderBy: 'id', limit: 1);
      await db.insert('teledoc_consultation', {
        'date_debut': start.toIso8601String(),
        'date_fin': start.add(const Duration(minutes: 18)).toIso8601String(),
        'type': TeledocConsultationType.video.apiValue,
        'ordonnance': 'Paracétamol 1 g : 1 comprimé 3 fois par jour, 5 jours.\n'
            'Pastilles pour la gorge au besoin.\n'
            'Reconsulter si la fièvre dépasse 39 °C.',
        'pharmacie_id': pharmacy.isEmpty ? null : pharmacy.first['id'],
        'demande_id': demandeId,
        'medecin_id': doctorIds.first,
      });
    }

    final fawzi = await userId('fawzi.saidi@esprit.tn');
    if (fawzi != null) {
      final created = now.subtract(const Duration(minutes: 10));
      await db.insert('teledoc_demande', {
        'motif': 'Douleur lombaire',
        'description': 'Douleur dans le bas du dos après un effort, '
            'difficulté à se pencher',
        'urgence': TeledocUrgency.moyenne.apiValue,
        'photo_symptome': null,
        'statut': TeledocRequestStatus.enAttente.apiValue,
        'patient_id': fawzi,
        'transaction_id': null,
        'cree_le': created.toIso8601String(),
        'modifie_le': created.toIso8601String(),
      });
    }
    summary.writeln('  démo        : 1 consultation terminée (client@), '
        '1 demande en file (fawzi)');
  }

  return summary.toString().trimRight();
}

Future<int> _count(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS c FROM $table')).first['c'] as int;
