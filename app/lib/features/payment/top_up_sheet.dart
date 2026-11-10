import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'payment_api.dart';
import 'payment_methods_screen.dart';

/// « Recharger mon solde »: credits the wallet from an already-registered
/// bank card (simulated charge server-side). Kept deliberately simple:
/// amount + card, nothing else. Without a card, sends the user to
/// [PaymentMethodsScreen] first.
class TopUpSheet extends StatefulWidget {
  const TopUpSheet({super.key, required this.api});

  final ApiClient api;

  /// Returns the credited amount in cents, or null when dismissed.
  static Future<int?> show(BuildContext context, {required ApiClient api}) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TopUpSheet(api: api),
    );
  }

  @override
  State<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<TopUpSheet> {
  late final PaymentApi _payments = PaymentApi(widget.api);
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  late Future<List<PaymentMethodDto>> _cardsFuture = _loadCards();
  int? _selectedCardId;
  bool _loading = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // Cards only: topping up from the wallet or cash would make no sense.
  Future<List<PaymentMethodDto>> _loadCards() async {
    final methods = await _payments.listMethods();
    return methods
        .where((m) => m.type == PaymentMethodType.carteBancaire)
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cents = parseAmountToCents(_amount.text);
    final cardId = _selectedCardId;
    if (cents == null || cardId == null) return;
    setState(() => _loading = true);
    try {
      await _payments.topUp(
          montantCentimes: cents, idMoyenPaiement: cardId);
      if (!mounted) return;
      Navigator.of(context).pop(cents);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Une erreur est survenue, veuillez réessayer')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_card_outlined,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recharger mon solde',
                          style: theme.textTheme.titleLarge),
                      Text('Depuis votre carte bancaire',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<List<PaymentMethodDto>>(
              future: _cardsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _cardsFuture = _loadCards()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  );
                }
                final cards = snapshot.data ?? const [];
                if (cards.isEmpty) {
                  return Column(
                    children: [
                      Text(
                        'Ajoutez d\'abord une carte bancaire pour '
                        'recharger votre portefeuille.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<PaymentMethodsScreen>(
                              builder: (_) =>
                                  PaymentMethodsScreen(api: widget.api),
                            ),
                          );
                          // The user may have added a card there.
                          if (mounted) {
                            setState(() => _cardsFuture = _loadCards());
                          }
                        },
                        icon: const Icon(Icons.credit_card),
                        label: const Text('Ajouter une carte'),
                      ),
                    ],
                  );
                }
                _selectedCardId ??= cards
                    .firstWhere((c) => c.parDefaut,
                        orElse: () => cards.first)
                    .id;
                return Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _amount,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Montant (DT)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (v) =>
                            parseAmountToCents(v ?? '') == null
                                ? 'Montant positif requis'
                                : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RadioGroup<int>(
                        groupValue: _selectedCardId,
                        onChanged: (v) {
                          if (!_loading) {
                            setState(() => _selectedCardId = v);
                          }
                        },
                        child: Column(
                          children: [
                            for (final c in cards)
                              RadioListTile<int>(
                                contentPadding: EdgeInsets.zero,
                                value: c.id,
                                title: Text(
                                    'Carte •••• ${c.quatreDerniersChiffres}'),
                                subtitle: c.parDefaut
                                    ? const Text('Par défaut')
                                    : null,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.add_card_outlined),
                        label: const Text('Recharger'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
