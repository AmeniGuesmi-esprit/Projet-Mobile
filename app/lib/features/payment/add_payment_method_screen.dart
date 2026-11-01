import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import 'payment_api.dart';

class AddPaymentMethodScreen extends StatefulWidget {
  const AddPaymentMethodScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AddPaymentMethodScreen> createState() => _AddPaymentMethodScreenState();
}

class _AddPaymentMethodScreenState extends State<AddPaymentMethodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardController = TextEditingController();
  final _holderController = TextEditingController();
  final _expiryController = TextEditingController();

  PaymentMethodType _type = PaymentMethodType.carteBancaire;
  bool _loading = false;
  String? _error;
  late final PaymentApi _payments = PaymentApi(widget.api);

  @override
  void dispose() {
    _cardController.dispose();
    _holderController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final created = await _payments.addMethod(
        type: _type,
        numeroCarte: _type == PaymentMethodType.carteBancaire
            ? _cardController.text
            : null,
        nomTitulaire: _type == PaymentMethodType.carteBancaire
            ? _holderController.text.trim()
            : null,
        dateExpiration: _type == PaymentMethodType.carteBancaire
            ? _expiryController.text.trim()
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created.type == PaymentMethodType.carteBancaire
                ? 'Carte •••• ${created.quatreDerniersChiffres} ajoutée'
                : 'Moyen de paiement ajouté',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue, veuillez réessayer');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un moyen de paiement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SegmentedButton<PaymentMethodType>(
              segments: const [
                ButtonSegment(
                  value: PaymentMethodType.carteBancaire,
                  label: Text('Carte'),
                  icon: Icon(Icons.credit_card),
                ),
                ButtonSegment(
                  value: PaymentMethodType.portefeuille,
                  label: Text('Portefeuille'),
                  icon: Icon(Icons.account_balance_wallet_outlined),
                ),
                ButtonSegment(
                  value: PaymentMethodType.especes,
                  label: Text('Espèces'),
                  icon: Icon(Icons.payments_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppSpacing.xl),
            Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _type == PaymentMethodType.carteBancaire
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _cardController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_CardNumberFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Numéro de carte',
                              prefixIcon: Icon(Icons.credit_card),
                              counterText: '',
                            ),
                            maxLength: 19,
                            validator: (v) => (v == null || !isValidCardNumber(v))
                                ? 'Numéro de carte invalide'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _holderController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Nom du titulaire',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => (v == null || v.trim().length < 2)
                                ? 'Nom du titulaire requis'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _expiryController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/]'))],
                            decoration: const InputDecoration(
                              labelText: 'Expiration (MM/AA)',
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            validator: (v) => (v == null || !isValidCardExpiry(v))
                                ? 'Format MM/AA, non expirée'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Seuls les 4 derniers chiffres sont conservés, jamais le numéro complet.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: AppColors.info, size: 20),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                _type == PaymentMethodType.portefeuille
                                    ? 'Votre portefeuille est crédité par vos remboursements internes.'
                                    : 'Paierez en main propre à la prestation.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Ajouter',
              isLoading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats card input as groups of 4 digits.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 19) {
      return TextEditingValue(
        text: oldValue.text,
        selection: oldValue.selection,
      );
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(
          digits.substring(i, (i + 4 > digits.length) ? digits.length : i + 4));
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
