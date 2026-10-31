import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/status_chip.dart';
import '../payment/new_payment_screen.dart';
import '../payment/payment_api.dart';
import '../payment/payment_methods_screen.dart';
import '../payment/transaction_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: session.refreshUser,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Bonjour ${user?.prenom ?? ''}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              'Bienvenue sur ProxiLife',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: AppColors.balanceCardGradient,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Solde disponible',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70)),
                      const Spacer(),
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.white70, size: 20),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  MoneyText(
                    user?.soldeCentimes ?? 0,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    user?.role.requiresRib == true
                        ? 'Revenus versés sur votre RIB'
                        : 'Portefeuille ProxiLife',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.payments_outlined,
                    label: 'Payer',
                    color: AppColors.accent,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) =>
                              NewPaymentScreen(session: session),
                        ),
                      );
                      await session.refreshUser();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.credit_card,
                    label: 'Mes moyens',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<PaymentMethodsScreen>(
                          builder: (_) =>
                              PaymentMethodsScreen(api: session.api),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Paiements',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _RecentTransactions(api: session.api),
          ],
        ),
      ),
    );
  }
}

/// The three most recent transactions, loaded once on first display.
class _RecentTransactions extends StatefulWidget {
  const _RecentTransactions({required this.api});

  final ApiClient api;

  @override
  State<_RecentTransactions> createState() => _RecentTransactionsState();
}

class _RecentTransactionsState extends State<_RecentTransactions> {
  late Future<List<TransactionDto>> _future = _load();

  Future<List<TransactionDto>> _load() =>
      PaymentApi(widget.api).listTransactions();

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<TransactionDto>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
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
            title: 'Aucun paiement pour le moment',
            message: 'Vos derniers paiements apparaîtront ici.',
            color: AppColors.moduleCompte,
          );
        }
        final recent = items.take(3).toList();
        return Column(
          children: [
            for (final t in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _RecentTile(
                  transaction: t,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<TransactionDetailScreen>(
                        builder: (_) => TransactionDetailScreen(
                          transaction: t,
                          api: widget.api,
                        ),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
            if (items.length > 3)
              Text(
                '… et ${items.length - 3} autre${items.length - 3 > 1 ? 's' : ''} dans l\'onglet Paiements',
                style: theme.textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.transaction, required this.onTap});

  final TransactionDto transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit =
        transaction.direction == TransactionDirection.credit;
    final counterparty = isCredit
        ? (transaction.payeurNom ?? transaction.payeurEmail ?? '—')
        : (transaction.beneficiaireNom ??
            transaction.beneficiaireEmail ??
            '—');
    final amountStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: isCredit ? AppColors.success : null,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
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
                    Row(
                      children: [
                        Text(isCredit ? '+ ' : '− ',
                            style: amountStyle),
                        MoneyText(
                          transaction.montantCentimes,
                          style: amountStyle,
                        ),
                      ],
                    ),
                    Text(
                      '${isCredit ? 'De' : 'À'} $counterparty',
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outlineSoft),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
