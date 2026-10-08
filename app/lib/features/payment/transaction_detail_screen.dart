import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/status_chip.dart';
import 'payment_api.dart';

/// Invoice view of a transaction, with refund / cancel actions.
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    required this.api,
  });

  final TransactionDto transaction;
  final ApiClient api;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late TransactionDto _transaction = widget.transaction;
  late final PaymentApi _payments = PaymentApi(widget.api);
  bool _loading = false;

  String _formatDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _refund() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Demander un remboursement ?'),
        content: Text(
          'Le montant de ${MoneyText.format(_transaction.montantCentimes)} sera recrédité sur votre portefeuille.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rembourser'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final updated = await _payments.refund(_transaction.id);
      await NotificationService.instance.show(
        title: 'Remboursement effectué',
        body:
            '${MoneyText.format(_transaction.montantCentimes)} recrédités sur votre portefeuille',
      );
      if (!mounted) return;
      setState(() => _transaction = updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Remboursement effectué')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler cette transaction ?'),
        content: const Text(
          'L\'annulation d\'une transaction en attente est immédiate et gratuite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annuler la transaction'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _payments.cancel(_transaction.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction annulée')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Facture')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.outlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ServiceBadge(_transaction.typeService),
                      const Spacer(),
                      StatusChip(_transaction.statut),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  MoneyText(
                    _transaction.montantCentimes,
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_transaction.factureNumero,
                      style: theme.textTheme.bodyMedium),
                  const Divider(height: AppSpacing.xl),
                  _row('Bénéficiaire',
                      _transaction.beneficiaireNom ?? '—'),
                  _row('E-mail', _transaction.beneficiaireEmail ?? '—'),
                  if (_transaction.idReference != null)
                    _row('Référence', _transaction.idReference!),
                  _row('Date', _formatDate(_transaction.dateIso)),
                  _row('Devise', _transaction.devise),
                  if (_transaction.idMoyenPaiement != null)
                    _row('Moyen de paiement',
                        'N° ${_transaction.idMoyenPaiement}'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (TransactionRules.canRefund(_transaction.statut))
                OutlinedButton.icon(
                  onPressed: _refund,
                  icon: const Icon(Icons.undo),
                  label: const Text('Rembourser'),
                ),
              if (TransactionRules.canCancel(_transaction.statut))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    onPressed: _cancel,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Annuler la transaction'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}
