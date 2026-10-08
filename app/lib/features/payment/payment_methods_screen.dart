import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import 'add_payment_method_screen.dart';
import 'payment_api.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  late Future<List<PaymentMethodDto>> _future;
  late final PaymentApi _payments = PaymentApi(widget.api);

  @override
  void initState() {
    super.initState();
    _future = _payments.listMethods();
  }

  void _reload() {
    setState(() {
      _future = _payments.listMethods();
    });
  }

  Future<void> _delete(PaymentMethodDto method) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce moyen ?'),
        content: Text(
          method.type == PaymentMethodType.carteBancaire
              ? 'Carte se terminant par ${method.quatreDerniersChiffres}'
              : switch (method.type) {
                  PaymentMethodType.portefeuille => 'Portefeuille interne',
                  _ => 'Paiement en espèces',
                },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _payments.deleteMethod(method.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Moyen supprimé')));
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _setDefault(PaymentMethodDto method) async {
    try {
      await _payments.setDefaultMethod(method.id);
      if (!mounted) return;
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Moyens de paiement',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Un paiement unifié pour tous les services ProxiLife.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<List<PaymentMethodDto>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorRetry(
                    onRetry: _reload,
                    message: 'Impossible de charger vos moyens de paiement',
                  );
                }
                final methods = snapshot.data ?? const [];
                if (methods.isEmpty) {
                  return const EmptyState(
                    icon: Icons.credit_card_outlined,
                    title: 'Aucun moyen de paiement',
                    message:
                        'Ajoutez une carte, un portefeuille ou le paiement en espèces.',
                  );
                }
                return Column(
                  children: [
                    for (final method in methods)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _MethodCard(
                          method: method,
                          onSetDefault: () => _setDefault(method),
                          onDelete: () => _delete(method),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<AddPaymentMethodScreen>(
                    builder: (_) =>
                        AddPaymentMethodScreen(api: widget.api),
                  ),
                );
                _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un moyen de paiement'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.onSetDefault,
    required this.onDelete,
  });

  final PaymentMethodDto method;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCard = method.type == PaymentMethodType.carteBancaire;
    final (icon, title, subtitle) = switch (method.type) {
      PaymentMethodType.carteBancaire => (
          Icons.credit_card,
          '•••• ${method.quatreDerniersChiffres ?? '----'}',
          '${method.nomTitulaire ?? ''} · expire ${method.dateExpiration ?? '-'}',
        ),
      PaymentMethodType.portefeuille => (
          Icons.account_balance_wallet_outlined,
          'Portefeuille ProxiLife',
          'Solde interne du compte',
        ),
      PaymentMethodType.especes => (
          Icons.payments_outlined,
          'Espèces',
          'Paiement en main propre',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: (isCard ? AppColors.primary : AppColors.moduleCompte)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (method.parDefaut) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text('Défaut',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Options du moyen de paiement',
              onSelected: (v) {
                if (v == 'default') onSetDefault();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                if (!method.parDefaut)
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Définir par défaut'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Supprimer',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textSecondary, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
                onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
