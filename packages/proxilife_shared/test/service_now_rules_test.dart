import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('state machines', () {
    test('a request follows the normal path', () {
      expect(
        ServiceNowRules.canMoveDemande(
            DemandeServiceStatus.enAttente, DemandeServiceStatus.acceptee),
        isTrue,
      );
      expect(
        ServiceNowRules.canMoveDemande(
            DemandeServiceStatus.acceptee, DemandeServiceStatus.enCours),
        isTrue,
      );
      expect(
        ServiceNowRules.canMoveDemande(
            DemandeServiceStatus.enCours, DemandeServiceStatus.terminee),
        isTrue,
      );
    });

    test('finished and cancelled requests are final', () {
      for (final to in DemandeServiceStatus.values) {
        expect(
            ServiceNowRules.canMoveDemande(DemandeServiceStatus.terminee, to),
            isFalse);
        expect(ServiceNowRules.canMoveDemande(DemandeServiceStatus.annulee, to),
            isFalse);
      }
    });

    test('an intervention cannot be finished before it starts', () {
      expect(
        ServiceNowRules.canMoveIntervention(
            InterventionStatus.planifiee, InterventionStatus.terminee),
        isFalse,
      );
    });

    test('a client cannot cancel work in progress', () {
      expect(ServiceNowRules.clientCanCancel(DemandeServiceStatus.acceptee),
          isTrue);
      expect(ServiceNowRules.clientCanCancel(DemandeServiceStatus.enCours),
          isFalse);
    });
  });

  group('payment', () {
    test('only finished, unpaid interventions are payable', () {
      expect(ServiceNowRules.canPay(InterventionStatus.terminee, null), isTrue);
      expect(
          ServiceNowRules.canPay(
              InterventionStatus.terminee, TransactionStatus.echoue),
          isTrue);
      expect(
          ServiceNowRules.canPay(
              InterventionStatus.terminee, TransactionStatus.paye),
          isFalse);
      expect(
          ServiceNowRules.canPay(
              InterventionStatus.terminee, TransactionStatus.enAttente),
          isFalse);
      expect(ServiceNowRules.canPay(InterventionStatus.enCours, null), isFalse);
    });
  });

  group('validation', () {
    final now = DateTime(2026, 6, 1, 12);

    test('description length', () {
      expect(ServiceNowRules.descriptionError('court'), isNotNull);
      expect(ServiceNowRules.descriptionError('Fuite sous l\'évier'), isNull);
    });

    test('address is required', () {
      expect(ServiceNowRules.addressError('   '), isNotNull);
      expect(ServiceNowRules.addressError('12 rue de Marseille, Tunis'), isNull);
    });

    test('schedule must be upcoming and within a year', () {
      expect(
          ServiceNowRules.scheduleError(
              now.subtract(const Duration(minutes: 1)),
              now: now),
          isNotNull);
      expect(
          ServiceNowRules.scheduleError(now.add(const Duration(days: 2)),
              now: now),
          isNull);
      expect(
          ServiceNowRules.scheduleError(now.add(const Duration(days: 366)),
              now: now),
          isNotNull);
    });

    test('price bounds', () {
      expect(ServiceNowRules.priceError(0), isNotNull);
      expect(ServiceNowRules.priceError(1), isNull);
      expect(ServiceNowRules.priceError(ServiceNowRules.maxPriceCentimes), isNull);
      expect(ServiceNowRules.priceError(ServiceNowRules.maxPriceCentimes + 1),
          isNotNull);
    });
  });

  group('matching', () {
    test('a closer specialist scores higher', () {
      final near = ServiceNowRules.matchScore(
          distanceKm: 1, specialty: true, rating: 4);
      final far = ServiceNowRules.matchScore(
          distanceKm: 40, specialty: true, rating: 4);
      final other = ServiceNowRules.matchScore(
          distanceKm: 1, specialty: false, rating: 4);
      expect(near, greaterThan(far));
      expect(near, greaterThan(other));
    });

    test('a better rating breaks the tie', () {
      double score(double rating) => ServiceNowRules.matchScore(
          distanceKm: 3, specialty: true, rating: rating);
      expect(score(5), greaterThan(score(2)));
    });
  });

  group('price estimate', () {
    test('uses the usual range without enough history', () {
      final (low, high, count) =
          ServiceNowRules.estimatePrice(ServiceNowType.menage, [1000, 2000]);
      expect((low, high), ServiceNowRules.defaultPriceRange(ServiceNowType.menage));
      expect(count, 0);
    });

    test('ignores extreme prices', () {
      final (low, high, count) = ServiceNowRules.estimatePrice(
          ServiceNowType.menage, [100, 3000, 3500, 4000, 90000]);
      expect(low, 3000);
      expect(high, 4000);
      expect(count, 5);
    });
  });

  group('rating', () {
    test('requires a payment and only happens once', () {
      expect(
          ServiceNowRules.canRate(InterventionStatus.terminee, null,
              alreadyRated: false),
          isFalse);
      expect(
          ServiceNowRules.canRate(
              InterventionStatus.terminee, TransactionStatus.paye,
              alreadyRated: false),
          isTrue);
      expect(
          ServiceNowRules.canRate(
              InterventionStatus.terminee, TransactionStatus.paye,
              alreadyRated: true),
          isFalse);
    });
  });

  group('availability', () {
    // 2026-06-01 is a Monday (weekday 1).
    final monday10 = DateTime(2026, 6, 1, 10);
    const mondayHours = [
      DisponibiliteSlotDto(jour: 1, debutMinutes: 480, finMinutes: 720),
    ];

    bool free(
      DateTime when, {
      List<DisponibiliteSlotDto> slots = const [],
      Set<String> off = const {},
      List<DateTime> busy = const [],
    }) =>
        ServiceNowRules.isAvailable(
          when,
          slots: slots,
          joursOff: off,
          busy: busy,
        );

    test('no calendar means always free', () {
      expect(free(monday10), isTrue);
    });

    test('follows the weekly hours', () {
      expect(free(monday10, slots: mondayHours), isTrue);
      expect(free(DateTime(2026, 6, 1, 13), slots: mondayHours), isFalse);
      expect(free(DateTime(2026, 6, 2, 10), slots: mondayHours), isFalse);
    });

    test('a day off wins over the hours', () {
      expect(free(monday10, slots: mondayHours, off: {'2026-06-01'}), isFalse);
    });

    test('interventions cannot overlap', () {
      expect(free(monday10, busy: [DateTime(2026, 6, 1, 11)]), isFalse);
      expect(free(monday10, busy: [DateTime(2026, 6, 1, 12)]), isTrue);
    });

    test('rejects a slot that ends before it starts', () {
      expect(
        ServiceNowRules.slotError(const DisponibiliteSlotDto(
            jour: 1, debutMinutes: 600, finMinutes: 600)),
        isNotNull,
      );
    });
  });

  test('DTOs survive a JSON round trip', () {
    final dto = DemandeServiceDto(
      id: 1,
      clientId: 2,
      clientNom: 'Ameni G.',
      type: ServiceNowType.plomberie,
      description: 'Fuite sous l\'évier',
      adresse: 'Tunis',
      dateSouhaitee: DateTime.utc(2026, 6, 2, 9),
      statut: DemandeServiceStatus.acceptee,
      creeLe: DateTime.utc(2026, 6, 1),
      modifieLe: DateTime.utc(2026, 6, 1),
      intervention: InterventionDto(
        id: 3,
        demandeId: 1,
        prestataireId: 4,
        datePrevue: DateTime.utc(2026, 6, 2, 10),
        prixCentimes: 4500,
        statut: InterventionStatus.planifiee,
        paiementStatut: TransactionStatus.paye,
      ),
    );

    final copy = DemandeServiceDto.fromJson(dto.toJson());

    expect(copy.toJson(), dto.toJson());
    expect(copy.intervention!.estPayee, isTrue);
  });
}
