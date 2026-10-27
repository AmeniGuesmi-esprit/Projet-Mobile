import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('haversineKm', () {
    test('same point is 0 km', () {
      expect(haversineKm(36.8065, 10.1815, 36.8065, 10.1815), 0);
    });

    test('Tunis centre → La Marsa is ~15 km', () {
      final d = haversineKm(36.8065, 10.1815, 36.8782, 10.3247);
      expect(d, closeTo(15.0, 0.6));
    });

    test('a point ~1.5 km away is inside the 5 km radius', () {
      final d = haversineKm(36.8065, 10.1815, 36.8100, 10.1650);
      expect(d, lessThan(foodSaveNotificationRadiusKm));
    });
  });

  group('isValidLatLng', () {
    test('accepts Tunis, rejects null island and out-of-range values', () {
      expect(isValidLatLng(36.8, 10.18), isTrue);
      expect(isValidLatLng(0, 0), isFalse);
      expect(isValidLatLng(91, 10), isFalse);
      expect(isValidLatLng(36, 181), isFalse);
      expect(isValidLatLng(double.nan, 10), isFalse);
    });
  });

  group('state machines', () {
    test('reservation: only en_attente can move', () {
      expect(
          FoodSaveRules.canTransitionReservation(
              ReservationStatus.enAttente, ReservationStatus.retire),
          isTrue);
      expect(
          FoodSaveRules.canTransitionReservation(
              ReservationStatus.retire, ReservationStatus.expire),
          isFalse);
      expect(
          FoodSaveRules.canTransitionReservation(
              ReservationStatus.expire, ReservationStatus.retire),
          isFalse);
    });

    test('basket: sold-out can go back on sale, terminal states cannot', () {
      expect(
          FoodSaveRules.canTransitionBasket(
              BasketStatus.epuise, BasketStatus.disponible),
          isTrue);
      expect(
          FoodSaveRules.canTransitionBasket(
              BasketStatus.annule, BasketStatus.disponible),
          isFalse);
    });
  });

  group('canReserve', () {
    final now = DateTime.utc(2026, 10, 13, 10);
    bool reserve({
      BasketStatus status = BasketStatus.disponible,
      int available = 3,
      int quantity = 1,
      Duration endIn = const Duration(hours: 2),
    }) =>
        FoodSaveRules.canReserve(
          status: status,
          available: available,
          quantity: quantity,
          pickupEnd: now.add(endIn),
          basketExpiry: now.add(const Duration(days: 1)),
          now: now,
        );

    test('nominal', () => expect(reserve(), isTrue));
    test('more than available', () => expect(reserve(quantity: 4), isFalse));
    test('zero quantity', () => expect(reserve(quantity: 0), isFalse));
    test('sold out', () => expect(reserve(status: BasketStatus.epuise), isFalse));
    test('pickup window about to close',
        () => expect(reserve(endIn: const Duration(minutes: 3)), isFalse));
  });

  group('reservation deadline', () {
    final end = DateTime.utc(2026, 10, 27, 23);

    test('closes "duration" before the end (min 5 min)', () {
      expect(
          FoodSaveRules.reservationDeadline(
              pickupEnd: end, reservationMinutes: 15),
          DateTime.utc(2026, 10, 27, 22, 45));
      expect(
          FoodSaveRules.reservationDeadline(
              pickupEnd: end, reservationMinutes: 0),
          DateTime.utc(2026, 10, 27, 22, 55));
    });

    bool can(DateTime now) => FoodSaveRules.canReserve(
          status: BasketStatus.disponible,
          available: 3,
          quantity: 1,
          pickupEnd: end,
          basketExpiry: end,
          now: now,
          reservationMinutes: 15,
        );

    test('22:44 can reserve, 22:45 cannot', () {
      expect(can(DateTime.utc(2026, 10, 27, 22, 44)), isTrue);
      expect(can(DateTime.utc(2026, 10, 27, 22, 45)), isFalse);
    });
  });

  group('qrExpiry', () {
    final start = DateTime.utc(2026, 10, 13, 18);
    final end = DateTime.utc(2026, 10, 13, 19);
    const ttl = Duration(minutes: 30);

    test('before the window: ttl counted from the opening', () {
      expect(
          FoodSaveRules.qrExpiry(
              now: DateTime.utc(2026, 10, 13, 12),
              pickupStart: start,
              pickupEnd: end,
              ttl: ttl),
          start.add(ttl));
    });

    test('inside the window: ttl after generation', () {
      final now = DateTime.utc(2026, 10, 13, 18, 10);
      expect(
          FoodSaveRules.qrExpiry(
              now: now, pickupStart: start, pickupEnd: end, ttl: ttl),
          now.add(ttl));
    });

    test('inside the window: capped at the window end', () {
      expect(
          FoodSaveRules.qrExpiry(
              now: DateTime.utc(2026, 10, 13, 18, 50),
              pickupStart: start,
              pickupEnd: end,
              ttl: ttl),
          end);
    });
  });

  group('basketError', () {
    final start = DateTime.utc(2026, 10, 13, 18);
    String? err({int price = 500, int initial = 1500, int qty = 3}) =>
        FoodSaveRules.basketError(
          title: 'Panier du soir',
          content: 'Pain, viennoiseries',
          priceCents: price,
          initialPriceCents: initial,
          quantity: qty,
          pickupStart: start,
          pickupEnd: start.add(const Duration(hours: 1)),
          expiry: start.add(const Duration(hours: 2)),
        );

    test('valid basket', () => expect(err(), isNull));
    test('expiry at least 1 h after the start', () {
      String? e(Duration open) => FoodSaveRules.basketError(
            title: 'Panier du soir',
            content: 'Pain, viennoiseries',
            priceCents: 500,
            initialPriceCents: 1500,
            quantity: 3,
            pickupStart: start,
            pickupEnd: start.add(open),
            expiry: start.add(open),
          );
      expect(e(const Duration(minutes: 59)), contains('au moins 1 h'));
      expect(e(const Duration(hours: 1)), isNull);
    });
    test('reservation duration between 5 and 240 minutes', () {
      String? e(int minutes) => FoodSaveRules.basketError(
            title: 'Panier du soir',
            content: 'Pain, viennoiseries',
            priceCents: 500,
            initialPriceCents: 1500,
            quantity: 3,
            pickupStart: start,
            pickupEnd: start.add(const Duration(hours: 2)),
            expiry: start.add(const Duration(hours: 2)),
            reservationMinutes: minutes,
          );
      expect(e(4), contains('durée de réservation'));
      expect(e(241), isNotNull);
      expect(e(5), isNull);
      expect(e(120), isNull);
      // Longer than the 2 h between the start and the expiry.
      expect(e(121), contains('ne peut pas dépasser'));
    });
    test('initial price must exceed reduced price',
        () => expect(err(initial: 500), isNotNull));
    test('negative quantity rejected', () => expect(err(qty: -1), isNotNull));
    test('discount percent', () {
      expect(FoodSaveRules.discountPercent(500, 1500), 67);
      expect(FoodSaveRules.discountPercent(1500, 1500), 0);
    });
  });

  test('DTO round-trip keeps UTC dates', () {
    final basket = BasketDto(
      id: 1,
      titre: 'Panier',
      contenu: 'Pain',
      categorie: FoodCategory.boulangerie,
      prixCentimes: 500,
      prixInitialCentimes: 1500,
      quantite: 2,
      quantiteInitiale: 3,
      creneauRetraitDebut: DateTime.utc(2026, 10, 13, 18),
      creneauRetraitFin: DateTime.utc(2026, 10, 13, 19),
      dateExpiration: DateTime.utc(2026, 10, 13, 22),
      statut: BasketStatus.disponible,
      commercantId: 7,
      creeLe: DateTime.utc(2026, 10, 13, 9),
      distanceKm: 1.25,
    );
    final copy = BasketDto.fromJson(basket.toJson());
    expect(copy.creneauRetraitDebut, basket.creneauRetraitDebut);
    expect(copy.creneauRetraitDebut.isUtc, isTrue);
    expect(copy.distanceKm, 1.25);
    expect(copy.statut, BasketStatus.disponible);
  });
}
