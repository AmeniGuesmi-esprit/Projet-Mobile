import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

TeledocQueueEntry entry(int id, TeledocUrgency urgence, int minute) =>
    TeledocQueueEntry(
      id: id,
      urgence: urgence,
      creeLe: DateTime(2026, 10, 14, 9, minute),
    );

void main() {
  group('TeledocQueue.order', () {
    test('urgence élevée d\'abord, puis ordre d\'arrivée', () {
      final ordered = TeledocQueue.order([
        entry(1, TeledocUrgency.faible, 0),
        entry(2, TeledocUrgency.moyenne, 5),
        entry(3, TeledocUrgency.elevee, 10),
        entry(4, TeledocUrgency.moyenne, 1),
      ]);
      expect(ordered.map((e) => e.id), [3, 4, 2, 1]);
    });

    test('l\'id départage deux demandes créées au même instant', () {
      final ordered = TeledocQueue.order([
        entry(9, TeledocUrgency.faible, 0),
        entry(7, TeledocUrgency.faible, 0),
      ]);
      expect(ordered.map((e) => e.id), [7, 9]);
    });
  });

  group('TeledocQueue.estimateWaitMinutes', () {
    test('exemple de la conception : p=5, M=2, D=15 → 30 min', () {
      expect(
        TeledocQueue.estimateWaitMinutes(
            position: 5, doctors: 2, averageMinutes: 15),
        30,
      );
    });

    test('les M premiers patients attendent ≈ 0 min', () {
      for (final p in [1, 2, 3]) {
        expect(
          TeledocQueue.estimateWaitMinutes(
              position: p, doctors: 3, averageMinutes: 20),
          0,
        );
      }
      expect(
        TeledocQueue.estimateWaitMinutes(
            position: 4, doctors: 3, averageMinutes: 20),
        20,
      );
    });

    test('aucun médecin actif : on compte comme un seul', () {
      expect(
        TeledocQueue.estimateWaitMinutes(
            position: 3, doctors: 0, averageMinutes: 10),
        20,
      );
    });

    test('position invalide', () {
      expect(
        () => TeledocQueue.estimateWaitMinutes(
            position: 0, doctors: 1, averageMinutes: 10),
        throwsArgumentError,
      );
    });
  });

  group('TeledocQueue.averageDurationMinutes', () {
    test('15 min par défaut sans historique', () {
      expect(TeledocQueue.averageDurationMinutes([]), 15);
    });

    test('moyenne arrondie', () {
      expect(
        TeledocQueue.averageDurationMinutes(const [
          Duration(minutes: 10),
          Duration(minutes: 21),
        ]),
        16, // 15,5 arrondi
      );
    });

    test('bornée entre 5 et 60 min', () {
      expect(
          TeledocQueue.averageDurationMinutes(const [Duration(minutes: 1)]), 5);
      expect(
          TeledocQueue.averageDurationMinutes(const [Duration(hours: 3)]), 60);
    });

    test('ignore les durées négatives', () {
      expect(
        TeledocQueue.averageDurationMinutes(const [
          Duration(minutes: -30),
          Duration(minutes: 12),
        ]),
        12,
      );
    });
  });

  group('TeledocQueue.places (temps dynamique)', () {
    final queue = [
      entry(1, TeledocUrgency.faible, 0),
      entry(2, TeledocUrgency.faible, 1),
      entry(3, TeledocUrgency.faible, 2),
    ];

    test('positions et temps pour toute la file', () {
      final places =
          TeledocQueue.places(queue, doctors: 1, averageMinutes: 10);
      expect(places[1]!.position, 1);
      expect(places[3]!.position, 3);
      expect(places[3]!.waitMinutes, 20);
    });

    test('une urgence fait reculer les autres', () {
      final places = TeledocQueue.places(
        [...queue, entry(4, TeledocUrgency.elevee, 30)],
        doctors: 1,
        averageMinutes: 10,
      );
      expect(places[4]!.position, 1);
      expect(places[3]!.position, 4);
      expect(places[3]!.waitMinutes, 30);
    });

    test('une annulation fait avancer les suivants', () {
      final places = TeledocQueue.places(
        queue.where((e) => e.id != 1),
        doctors: 1,
        averageMinutes: 10,
      );
      expect(places[3]!.position, 2);
      expect(places[3]!.waitMinutes, 10);
    });
  });

  test('isSoon : position ≤ 2', () {
    expect(TeledocQueue.isSoon(1), isTrue);
    expect(TeledocQueue.isSoon(2), isTrue);
    expect(TeledocQueue.isSoon(3), isFalse);
  });
}
