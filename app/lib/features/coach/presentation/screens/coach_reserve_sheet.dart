import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../payment/add_payment_method_screen.dart';
import '../../../payment/payment_api.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';

/// Bottom sheet that books one seat: summary, payment method, confirmation.
/// Pops the created [CoachBookingDto] on success.
class CoachReserveSheet extends StatefulWidget {
  const CoachReserveSheet({
    super.key,
    required this.session,
    required this.coachSession,
  });

  final SessionController session;
  final CoachSessionDto coachSession;

  @override
  State<CoachReserveSheet> createState() => _CoachReserveSheetState();
}

class _CoachReserveSheetState extends State<CoachReserveSheet> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late final PaymentApi _payments = PaymentApi(widget.session.api);

  List<PaymentMethodDto>? _methods;
  Object? _methodsError;
  bool _loadingMethods = false;
  int? _selectedId;

  bool _submitting = false;
  String? _error;

  bool get _free => widget.coachSession.isFree;
  int get _price => widget.coachSession.prixCentimes;
  int get _balance => widget.session.user?.soldeCentimes ?? 0;

  PaymentMethodDto? get _selected {
    final methods = _methods;
    if (methods == null) return null;
    for (final m in methods) {
      if (m.id == _selectedId) return m;
    }
    return null;
  }

  bool get _walletTooLow =>
      _selected?.type == PaymentMethodType.portefeuille && _balance < _price;

  bool get _canConfirm =>
      !_submitting && (_free || (_selected != null && !_walletTooLow));

  @override
  void initState() {
    super.initState();
    if (!_free) unawaited(_loadMethods());
  }

  Future<void> _loadMethods({bool preferNew = false}) async {
    final previousIds = _methods?.map((m) => m.id).toSet() ?? <int>{};
    setState(() {
      _loadingMethods = true;
      _methodsError = null;
    });
    try {
      final methods = await _payments.listMethods();
      if (!mounted) return;
      int? selected = _selectedId;
      if (preferNew) {
        for (final m in methods) {
          if (!previousIds.contains(m.id)) selected = m.id;
        }
      }
      if (selected == null || !methods.any((m) => m.id == selected)) {
        final defaults = methods.where((m) => m.parDefaut);
        selected = defaults.isNotEmpty
            ? defaults.first.id
            : (methods.isEmpty ? null : methods.first.id);
      }
      setState(() {
        _methods = methods;
        _selectedId = selected;
        _loadingMethods = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _methodsError = e;
        _loadingMethods = false;
      });
    }
  }

  Future<void> _addMethod() async {
    await pushCoach<void>(
      context,
      AddPaymentMethodScreen(api: widget.session.api),
    );
    if (mounted) await _loadMethods(preferNew: true);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final booking = await _api.reserve(
        widget.coachSession.id,
        paymentMethodId: _free ? null : _selectedId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(booking);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = coachErrorMessage(e);
      });
    }
  }

  Widget _paymentSection(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingMethods && _methods == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_methodsError != null && _methods == null) {
      return CoachErrorRetry(
        message: coachErrorMessage(_methodsError!),
        onRetry: _loadMethods,
      );
    }
    final methods = _methods ?? const <PaymentMethodDto>[];
    if (methods.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajoutez un moyen de paiement (carte, portefeuille ou espèces) '
            'pour réserver cette séance.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _addMethod,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Ajouter un moyen de paiement'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _MethodOption(
              method: m,
              selected: m.id == _selectedId,
              balance: _balance,
              price: _price,
              onTap: () => setState(() => _selectedId = m.id),
            ),
          ),
        TextButton.icon(
          onPressed: _addMethod,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un moyen de paiement'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.coachSession;
    final cash = _selected?.type == PaymentMethodType.especes;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Réserver ma place', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: CoachColors.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    CoachTypeAvatar(s.type),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.titre, style: theme.textTheme.titleMedium),
                          Text(coachWhen(s.dateHeure),
                              style: theme.textTheme.bodyMedium),
                          Text(s.lieu,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    coachPrice(_price),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: CoachColors.brandDeep),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_free)
                Text(
                  'Séance gratuite : aucun paiement n\'est nécessaire.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                Text('Moyen de paiement', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                _paymentSection(context),
              ],
              if (cash)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Vous réglez en espèces au coach le jour de la séance : '
                    'il confirme le paiement en scannant votre QR code.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (_walletTooLow)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Solde insuffisant : choisissez une autre méthode ou '
                    'rechargez votre portefeuille.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.error),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: _free ? 'Confirmer la réservation' : 'Payer et réserver',
                icon: Icons.check_circle_outline,
                isLoading: _submitting,
                onPressed: _canConfirm ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable "radio card" for one saved payment method.
class _MethodOption extends StatelessWidget {
  const _MethodOption({
    required this.method,
    required this.selected,
    required this.balance,
    required this.price,
    required this.onTap,
  });

  final PaymentMethodDto method;
  final bool selected;
  final int balance;
  final int price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = coachMethodTitle(method);
    final icon = switch (method.type) {
      PaymentMethodType.carteBancaire => Icons.credit_card,
      PaymentMethodType.portefeuille => Icons.account_balance_wallet_outlined,
      PaymentMethodType.especes => Icons.payments_outlined,
    };
    final subtitle = switch (method.type) {
      PaymentMethodType.carteBancaire => [
          if (method.nomTitulaire != null) method.nomTitulaire!,
          if (method.dateExpiration != null) 'expire ${method.dateExpiration}',
        ].join(' · '),
      PaymentMethodType.portefeuille => 'Solde : ${MoneyText.format(balance)}'
          '${balance < price ? ' — insuffisant' : ''}',
      PaymentMethodType.especes => 'À régler au coach le jour de la séance',
    };
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '$title${method.parDefaut ? ', par défaut' : ''}',
      child: Material(
        color: selected ? CoachColors.brandSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? CoachColors.brandDeep : AppColors.outline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: CoachColors.brandDeep),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.parDefaut ? '$title · par défaut' : title,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color:
                      selected ? CoachColors.brandDeep : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
