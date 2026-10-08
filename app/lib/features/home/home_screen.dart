import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';

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
                  Text(
                    '${((user?.soldeCentimes ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')} €',
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
