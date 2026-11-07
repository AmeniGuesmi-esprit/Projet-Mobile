import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// CoachProche demo data: a few upcoming sessions for the demo coach
/// (yasmine.chakroun@esprit.tn). Idempotent: nothing is added while the coach
/// still has an upcoming session. Returns a log line for `bin/seed.dart`.
///
/// The first session starts in 15 minutes, so the presence scan (open from
/// 30 minutes before the start) can be tried right after seeding.
Future<String> seedCoach(Database db, int? coachId) async {
  if (coachId == null) return 'Coach    : aucun coach, séances non créées';
  final now = DateTime.now().toUtc();
  final nowIso = now.toIso8601String();

  final upcoming = (await db.rawQuery(
    "SELECT COUNT(*) AS c FROM coach_seance WHERE coach_id = ? "
    "AND statut = 'planifiee' AND date_heure > ?",
    [coachId, nowIso],
  ))
      .first['c'] as int;
  if (upcoming > 0) {
    return 'Coach    : $upcoming séance(s) à venir déjà présente(s)';
  }

  // (titre, description, type, lieu, lat, lng, début, durée, niveau,
  //  places, prix en centimes)
  final sessions = <(String, String, String, String, double, double, Duration,
      int, String, int, int)>[
    (
      'Fitness express',
      'Circuit cardio de 45 minutes, apportez une serviette et de l\'eau.',
      'fitness',
      'Avenue Habib Bourguiba, Tunis',
      36.8008,
      10.1800,
      const Duration(minutes: 15),
      45,
      'intermediaire',
      8,
      1000,
    ),
    (
      'Yoga au lever du soleil',
      'Salutations au soleil, respiration et relaxation. Tapis fournis.',
      'yoga',
      'Parc du Belvédère, Tunis',
      36.8200,
      10.1750,
      const Duration(hours: 20),
      60,
      'debutant',
      12,
      1500,
    ),
    (
      'Running — Berges du Lac',
      'Sortie à allure modérée autour du lac, 8 km. Séance gratuite.',
      'running',
      'Berges du Lac, Tunis',
      36.8330,
      10.2310,
      const Duration(days: 2),
      90,
      'intermediaire',
      20,
      0,
    ),
    (
      'Cross-training intensif',
      'Renforcement musculaire par intervalles, pour sportifs confirmés.',
      'musculation',
      'La Marsa, Tunis',
      36.8782,
      10.3247,
      const Duration(days: 3),
      60,
      'avance',
      10,
      2000,
    ),
    (
      'Zumba du dimanche',
      'Cours de danse fitness sur des rythmes latinos, tous niveaux.',
      'danse',
      'Sidi Bou Saïd, Tunis',
      36.8700,
      10.3410,
      const Duration(days: 4),
      60,
      'debutant',
      25,
      800,
    ),
  ];

  for (final (titre, description, type, lieu, lat, lng, start, duree, niveau,
      places, prix) in sessions) {
    await db.insert('coach_seance', {
      'titre': titre,
      'description': description,
      'type': type,
      'lieu': lieu,
      'latitude': lat,
      'longitude': lng,
      'date_heure': now.add(start).toIso8601String(),
      'duree_minutes': duree,
      'niveau': niveau,
      'places_totales': places,
      'places_restantes': places,
      'prix_centimes': prix,
      'statut': 'planifiee',
      'coach_id': coachId,
      'cree_le': nowIso,
      'mis_a_jour_le': nowIso,
    });
  }
  return 'Coach    : ${sessions.length} séances de démonstration créées';
}
