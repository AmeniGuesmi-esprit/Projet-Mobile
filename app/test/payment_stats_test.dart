import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/features/payment/payment_stats.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

TransactionDto tx({
  required int id,
  required int cents,
  required TransactionStatus statut,
  required ServiceType service,
  required TransactionDirection direction,
  required String dateIso,
}) =>
    TransactionDto(
      id: id,
      montantCentimes: cents,
      devise: 'TND',
      dateIso: dateIso,
      statut: statut,
      typeService: service,
      factureNumero: 'FAC-2026-${id.toString().padLeft(6, '0')}',
      direction: direction,
    );

void main() {
  final now = DateTime(2026, 10, 31, 15, 30);
  String iso(DateTime d) => d.toIso8601String();

  group('PaymentStats', () {
    test('empty history yields zeroes and seven empty days', () {
      final stats = PaymentStats.fromTransactions(const [], now: now);
      expect(stats.totalEnvoyeCentimes, 0);
      expect(stats.totalRecuCentimes, 0);
      expect(stats.nombreTransactions, 0);
      expect(stats.jours, hasLength(7));
      expect(stats.jours.every((j) => j.total == 0), isTrue);
      expect(stats.jours.last.day, DateTime(2026, 10, 31));
    });

    test('only paye transactions count; debit/credit split by service & day',
        () {
      final items = [
        tx(
            id: 1,
            cents: 1000,
            statut: TransactionStatus.paye,
            service: ServiceType.ecoRoute,
            direction: TransactionDirection.debit,
            dateIso: iso(now)),
        tx(
            id: 2,
            cents: 2500,
            statut: TransactionStatus.paye,
            service: ServiceType.foodSave,
            direction: TransactionDirection.credit,
            dateIso: iso(now.subtract(const Duration(days: 1)))),
        tx(
            id: 3,
            cents: 900,
            statut: TransactionStatus.echoue,
            service: ServiceType.ecoRoute,
            direction: TransactionDirection.debit,
            dateIso: iso(now)),
        tx(
            id: 4,
            cents: 300,
            statut: TransactionStatus.rembourse,
            service: ServiceType.teleDoc,
            direction: TransactionDirection.debit,
            dateIso: iso(now)),
        tx(
            id: 5,
            cents: 450,
            statut: TransactionStatus.enAttente,
            service: ServiceType.serviceNow,
            direction: TransactionDirection.debit,
            dateIso: iso(now)),
      ];
      final stats = PaymentStats.fromTransactions(items, now: now);

      expect(stats.totalEnvoyeCentimes, 1000); // only #1 (paye + debit)
      expect(stats.totalRecuCentimes, 2500); // only #2
      expect(stats.nombreTransactions, 5); // everything is counted in total
      expect(stats.debitParService, {ServiceType.ecoRoute: 1000});

      final today = stats.jours.last;
      expect(today.envoye, 1000);
      expect(today.recu, 0);
      final yesterday = stats.jours[stats.jours.length - 2];
      expect(yesterday.recu, 2500);
      expect(DateTime(yesterday.day.year, yesterday.day.month,
          yesterday.day.day), DateTime(2026, 10, 30));
    });

    test('days outside the 7-day window are ignored by the chart', () {
      final items = [
        tx(
            id: 1,
            cents: 500,
            statut: TransactionStatus.paye,
            service: ServiceType.ecoRoute,
            direction: TransactionDirection.debit,
            dateIso: iso(now.subtract(const Duration(days: 30)))),
      ];
      final stats = PaymentStats.fromTransactions(items, now: now);
      expect(stats.totalEnvoyeCentimes, 500); // counted in totals…
      expect(stats.jours.every((j) => j.total == 0), isTrue); // …not in chart
    });
  });
}
