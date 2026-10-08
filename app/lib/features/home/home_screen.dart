import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../payment/new_payment_screen.dart';
import '../payment/payment_methods_screen.dart';

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
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Aucun paiement pour le moment',
              message: 'L\'historique arrive avec le module Paiement.',
              color: AppColors.moduleCompte,
            ),
          ],
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
