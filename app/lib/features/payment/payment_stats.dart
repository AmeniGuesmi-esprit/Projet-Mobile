import 'package:proxilife_shared/proxilife_shared.dart';

/// One day of aggregated activity (sent + received, whole cents).
class DailyTotal {
  const DailyTotal({required this.day, required this.envoye, required this.recu});

  final DateTime day;
  final int envoye;
  final int recu;

  int get total => envoye + recu;
}

/// Aggregated payment statistics computed client-side from the transaction
/// history. Pure logic — no Flutter imports — so it is unit-testable.
class PaymentStats {
  const PaymentStats({
    required this.totalEnvoyeCentimes,
    required this.totalRecuCentimes,
    required this.nombreTransactions,
    required this.debitParService,
    required this.jours,
  });

  /// Money sent (debit) with status `paye` — refunded amounts excluded.
  final int totalEnvoyeCentimes;

  /// Money received (credit) with status `paye`.
  final int totalRecuCentimes;

  /// All visible transactions regardless of status.
  final int nombreTransactions;

  /// Sent amounts grouped by service (status `paye` only).
  final Map<ServiceType, int> debitParService;

  /// The last 7 calendar days, oldest first, always 7 entries.
  final List<DailyTotal> jours;

  /// Short weekday labels matching [jours] indices (1 = Monday).
  static const List<String> dayLabels = <String>[
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];

  factory PaymentStats.fromTransactions(
    List<TransactionDto> items, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);

    var totalEnvoye = 0;
    var totalRecu = 0;
    final parService = <ServiceType, int>{};
    final parJour = <DateTime, DailyTotal>{};
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      parJour[day] = DailyTotal(day: day, envoye: 0, recu: 0);
    }

    for (final t in items) {
      if (t.statut != TransactionStatus.paye) continue;
      final isCredit = t.direction == TransactionDirection.credit;
      if (isCredit) {
        totalRecu += t.montantCentimes;
      } else {
        totalEnvoye += t.montantCentimes;
        parService.update(
          t.typeService,
          (v) => v + t.montantCentimes,
          ifAbsent: () => t.montantCentimes,
        );
      }

      final date = DateTime.tryParse(t.dateIso);
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        final entry = parJour[day];
        if (entry != null) {
          parJour[day] = DailyTotal(
            day: day,
            envoye: entry.envoye + (isCredit ? 0 : t.montantCentimes),
            recu: entry.recu + (isCredit ? t.montantCentimes : 0),
          );
        }
      }
    }

    return PaymentStats(
      totalEnvoyeCentimes: totalEnvoye,
      totalRecuCentimes: totalRecu,
      nombreTransactions: items.length,
      debitParService: parService,
      jours: parJour.values.toList(),
    );
  }
}
