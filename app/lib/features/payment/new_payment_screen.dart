import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/service_badge.dart';
import 'payment_api.dart';

class NewPaymentScreen extends StatefulWidget {
  const NewPaymentScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<NewPaymentScreen> createState() => _NewPaymentScreenState();
}

class _NewPaymentScreenState extends State<NewPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _beneficiaryController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  late final PaymentApi _payments = PaymentApi(widget.session.api);

  late Future<List<PaymentMethodDto>> _methodsFuture;
  ServiceType _service = ServiceType.ecoRoute;
  int? _selectedMethodId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _methodsFuture = _payments.listMethods();
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final cents = parseAmountToCents(_amountController.text);
    if (cents == null) return;
    setState(() => _loading = true);
    try {
      final tx = await _payments.createTransaction(
        montantCentimes: cents,
        beneficiaireEmail: _beneficiaryController.text.trim(),
        typeService: _service,
        idReference: _referenceController.text.trim(),
        idMoyenPaiement: _selectedMethodId,
      );
      if (tx.statut == TransactionStatus.paye) {
        await NotificationService.instance.show(
          title: 'Paiement effectué',
          body: '${MoneyText.format(cents)} — ${ServiceMeta.of(_service).label}',
        );
      } else {
        await NotificationService.instance.show(
          title: 'Paiement échoué',
          body: 'Solde du portefeuille insuffisant',
        );
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            tx.statut == TransactionStatus.paye
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: tx.statut == TransactionStatus.paye
                ? AppColors.success
                : AppColors.error,
            size: 44,
          ),
          title: Text(tx.statut == TransactionStatus.paye
              ? 'Paiement effectué'
              : 'Paiement échoué'),
          content: Text(
            tx.statut == TransactionStatus.paye
                ? '${MoneyText.format(cents)} vers ${tx.beneficiaireNom ?? tx.beneficiaireEmail ?? ''}\nFacture ${tx.factureNumero}'
                : 'Rechargez votre portefeuille ou choisissez une autre méthode.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('Nouveau paiement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35)),
                ),
                child: Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.error)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _beneficiaryController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Bénéficiaire (e-mail)',
                      prefixIcon: Icon(Icons.person_search_outlined),
                      helperText:
                          'Le compte ProxiLife du professionnel à payer',
                    ),
                    validator: (v) => (v == null || !isValidEmail(v))
                        ? 'E-mail invalide'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Montant (€)',
                      prefixIcon: Icon(Icons.euro),
                    ),
                    validator: (v) {
                      final cents = parseAmountToCents(v ?? '');
                      return cents == null ? 'Montant positif requis' : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Service', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final type in ServiceType.values)
                        GestureDetector(
                          onTap: () => setState(() => _service = type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: _service == type
                                    ? ServiceMeta.of(type).color
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: ServiceBadge(type),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _referenceController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Référence (optionnel)',
                      prefixIcon: Icon(Icons.tag),
                      helperText: 'Réservation, consultation ou intervention',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FutureBuilder<List<PaymentMethodDto>>(
                    future: _methodsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child:
                              Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(
                          'Moyens de paiement indisponibles — réessayez',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.error),
                        );
                      }
                      final methods = snapshot.data ?? const [];
                      if (methods.isEmpty) {
                        return Text(
                          'Ajoutez d\'abord un moyen de paiement dans l\'onglet Paiements.',
                          style: theme.textTheme.bodyMedium,
                        );
                      }
                      final defaultMethod = methods.firstWhere(
                        (m) => m.parDefaut,
                        orElse: () => methods.first,
                      );
                      _selectedMethodId ??= defaultMethod.id;
                      return InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Moyen de paiement',
                          contentPadding: EdgeInsets.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: RadioGroup<int>(
                            groupValue: _selectedMethodId,
                            onChanged: (v) =>
                                setState(() => _selectedMethodId = v),
                            child: Column(
                              children: [
                                for (final m in methods)
                                  RadioListTile<int>(
                                    contentPadding: EdgeInsets.zero,
                                    value: m.id,
                                    title: Text(
                                      m.type == PaymentMethodType.carteBancaire
                                          ? 'Carte •••• ${m.quatreDerniersChiffres}'
                                          : m.type == PaymentMethodType.portefeuille
                                              ? 'Portefeuille ProxiLife'
                                              : 'Espèces',
                                    ),
                                    subtitle: m.parDefaut
                                        ? const Text('Par défaut')
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Payer',
                    icon: Icons.payments_outlined,
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
