import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/money_text.dart';
import 'payment_api.dart';
import 'payment_methods_screen.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  late final PaymentApi _payments = PaymentApi(widget.api);

  late Future<List<TransactionDto>> _future;
  TransactionStatus? _statutFilter;
  ServiceType? _serviceFilter;

  @override
  void initState() {
    super.initState();
    _future = _payments.listTransactions();
  }

  /// Public: lets the parent reload after a payment was created.
  void reload() => _reload();

  void _reload() {
    setState(() {
      _future = _payments.listTransactions(
        statut: _statutFilter,
        service: _serviceFilter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Paiements',
                          style: theme.textTheme.headlineMedium),
                    ),
                    IconButton(
                      tooltip: 'Moyens de paiement',
                      icon: const Icon(Icons.credit_card,
                          color: AppColors.primary),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<PaymentMethodsScreen>(
                            builder: (_) =>
                                PaymentMethodsScreen(api: widget.api),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                Text('Votre historique et vos factures',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                _filterChip('Tous', _statutFilter == null && _serviceFilter == null,
                    () => setState(() {
                          _statutFilter = null;
                          _serviceFilter = null;
                        })),
                const SizedBox(width: AppSpacing.xs),
                for (final s in TransactionStatus.values) ...[
                  _filterChip(
                    switch (s) {
                      TransactionStatus.enAttente => 'En attente',
                      TransactionStatus.paye => 'Payé',
                      TransactionStatus.echoue => 'Échoué',
                      TransactionStatus.rembourse => 'Remboursé',
                    },
                    _statutFilter == s,
                    () => setState(() => _statutFilter =
                        _statutFilter == s ? null : s),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                for (final t in ServiceType.values) ...[
                  _filterChip(
                    ServiceMeta.of(t).label,
                    _serviceFilter == t,
                    () => setState(() => _serviceFilter =
                        _serviceFilter == t ? null : t),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
          Expanded(
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
                    icon: Icons.receipt_long_outlined,
                    title: 'Aucune transaction',
                    message:
                        'Payez un service ProxiLife pour la voir ici.',
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _TransactionTile(
                      transaction: items[i],
                      api: widget.api,
                      onChanged: _reload,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        onTap();
        _reload();
      },
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.api,
    required this.onChanged,
  });

  final TransactionDto transaction;
  final ApiClient api;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.tryParse(transaction.dateIso);
    final formattedDate = date == null
        ? transaction.dateIso
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<TransactionDetailScreen>(
              builder: (_) => TransactionDetailScreen(
                transaction: transaction,
                api: api,
              ),
            ),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ServiceBadge(transaction.typeService, compact: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoneyText(
                      transaction.montantCentimes,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${transaction.beneficiaireNom ?? transaction.beneficiaireEmail ?? '—'} · $formattedDate',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusChip(transaction.statut),
            ],
          ),
        ),
      ),
    );
  }
}
