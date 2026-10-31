import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/service_badge.dart';
import 'payment_api.dart';
import 'payment_stats.dart';

/// Spending insights: totals, per-service split and the last 7 days.
/// Everything is computed client-side from the transaction history.
class PaymentStatsScreen extends StatefulWidget {
  const PaymentStatsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<PaymentStatsScreen> createState() => _PaymentStatsScreenState();
}

class _PaymentStatsScreenState extends State<PaymentStatsScreen> {
  late final PaymentApi _payments = PaymentApi(widget.api);
  late Future<List<TransactionDto>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _payments.listTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: SafeArea(
        child: FutureBuilder<List<TransactionDto>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              );
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.bar_chart,
                title: 'Pas encore de données',
                message: 'Vos statistiques apparaîtront après un paiement.',
              );
            }
            final stats = PaymentStats.fromTransactions(items);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text('Vue d\'ensemble', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _TotalCard(
                        label: 'Envoyé',
                        icon: Icons.north_east,
                        color: AppColors.text,
                        cents: stats.totalEnvoyeCentimes,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _TotalCard(
                        label: 'Reçu',
                        icon: Icons.south_west,
                        color: AppColors.success,
                        cents: stats.totalRecuCentimes,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('7 derniers jours',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _WeekChart(jours: stats.jours),
                const SizedBox(height: AppSpacing.lg),
                Text('Par service', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (stats.debitParService.isEmpty)
                  Text('Aucun paiement envoyé pour le moment.',
                      style: theme.textTheme.bodyMedium)
                else
                  _ServiceBars(parService: stats.debitParService),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Text(
                    '${stats.nombreTransactions} transaction${stats.nombreTransactions > 1 ? 's' : ''} au total',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.cents,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int cents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          MoneyText(
            cents,
            style: theme.textTheme.headlineMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.jours});

  final List<DailyTotal> jours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = jours.fold<int>(
        1, (max, j) => j.total > max ? j.total : max);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final j in jours)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Semantics(
                      label:
                          '${PaymentStats.dayLabels[j.day.weekday - 1]} : ${MoneyText.format(j.total)}',
                      child: SizedBox(
                        height: 96,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            heightFactor:
                                (j.total / maxTotal).clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                gradient: j.envoye >= j.recu
                                    ? AppColors.balanceCardGradient
                                    : const LinearGradient(
                                        colors: [
                                          AppColors.success,
                                          AppColors.primary,
                                        ],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      PaymentStats.dayLabels[j.day.weekday - 1],
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceBars extends StatelessWidget {
  const _ServiceBars({required this.parService});

  final Map<ServiceType, int> parService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = parService.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxAmount = entries.first.value;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ServiceBadge(entry.key, compact: true),
                      const SizedBox(width: AppSpacing.sm),
                      MoneyText(
                        entry.value,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      widthFactor:
                          (entry.value / maxAmount).clamp(0.03, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 8,
                        decoration: const BoxDecoration(
                          gradient: AppColors.balanceCardGradient,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
