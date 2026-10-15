import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../payment/add_payment_method_screen.dart';
import '../../../payment/payment_api.dart';
import '../../data/foodsave_api.dart';
import '../../widgets/foodsave_ui.dart';
import '../widgets/client_format.dart';
import 'booking_format.dart';
import 'payment_method_option.dart';

/// Maximum units per reservation (mirrors the server rule).
const int maxUnitsPerReservation = 20;

/// Legal / expectation note shown before paying.
const String qrExpiryNote =
    'Le QR code expire à la fin du créneau (ou 30 min après sa génération '
    'pendant le créneau). Passé ce délai, le panier est remis en vente sans '
    'remboursement automatique.';

enum ReserveStep { quantity, payment, summary, success }

/// Content of the reservation bottom sheet (see `showReserveFlow`).
/// Pops the created [ReservationDto] on success.
class ReserveSheet extends StatefulWidget {
  const ReserveSheet({super.key, required this.session, required this.basket});

  final SessionController session;
  final BasketDto basket;

  @override
  State<ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends State<ReserveSheet> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late final PaymentApi _payments = PaymentApi(widget.session.api);

  late BasketDto _basket = widget.basket;
  ReserveStep _step = ReserveStep.quantity;
  int _quantity = 1;

  List<PaymentMethodDto>? _methods;
  Object? _methodsError;
  bool _methodsLoading = false;
  int? _selectedMethodId;

  bool _submitting = false;
  ApiException? _error;

  int get _maxQuantity =>
      math.max(0, math.min(_basket.quantite, maxUnitsPerReservation));
  int get _total => _basket.prixCentimes * _quantity;
  int get _savings =>
      math.max(0, _basket.prixInitialCentimes - _basket.prixCentimes) *
      _quantity;

  PaymentMethodDto? get _selectedMethod {
    final methods = _methods;
    if (methods == null) return null;
    for (final m in methods) {
      if (m.id == _selectedMethodId) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_maxQuantity == 0) _quantity = 0;
    _loadMethods(); // preloaded while the user picks a quantity
  }

  Future<void> _loadMethods({bool preferNew = false}) async {
    final previousIds = _methods?.map((m) => m.id).toSet() ?? <int>{};
    setState(() {
      _methodsLoading = true;
      _methodsError = null;
    });
    try {
      final methods = await _payments.listMethods();
      if (!mounted) return;
      int? selected = _selectedMethodId;
      if (preferNew) {
        for (final m in methods) {
          if (!previousIds.contains(m.id)) selected = m.id;
        }
      }
      if (selected == null || !methods.any((m) => m.id == selected)) {
        final byDefault = methods.where((m) => m.parDefaut);
        selected = byDefault.isNotEmpty
            ? byDefault.first.id
            : (methods.isEmpty ? null : methods.first.id);
      }
      setState(() {
        _methods = methods;
        _selectedMethodId = selected;
        _methodsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _methodsError = e;
        _methodsLoading = false;
      });
    }
  }

  Future<void> _addMethod() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddPaymentMethodScreen(api: widget.session.api),
    ));
    if (mounted) await _loadMethods(preferNew: true);
  }

  void _goTo(ReserveStep step) => setState(() {
        _step = step;
        if (step != ReserveStep.summary) _error = null;
      });

  void _back() {
    switch (_step) {
      case ReserveStep.payment:
        _goTo(ReserveStep.quantity);
      case ReserveStep.summary:
        _goTo(ReserveStep.payment);
      case ReserveStep.quantity:
      case ReserveStep.success:
        Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirm() async {
    final method = _selectedMethod;
    if (method == null || _quantity < 1 || _submitting) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final reservation = await _api.reserve(
        panierId: _basket.id,
        quantite: _quantity,
        moyenPaiementId: method.id,
      );
      if (method.type == PaymentMethodType.portefeuille) {
        unawaited(widget.session.refreshUser().catchError((Object e) {
          developer.log('Balance refresh failed: $e', name: 'foodsave');
        }));
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _step = ReserveStep.success;
      });
      await Future<void>.delayed(
          reduceMotion ? Duration.zero : const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(reservation);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e;
      });
      if (e.statusCode == 409) unawaited(_refreshBasket());
    } catch (e) {
      developer.log('Reservation failed: $e', name: 'foodsave');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = const ApiException(
            500, 'Une erreur inattendue est survenue. Veuillez réessayer.');
      });
    }
  }

  /// After a conflict the stock may have changed: refresh the bounds.
  Future<void> _refreshBasket() async {
    try {
      final fresh = await _api.getBasket(_basket.id);
      if (!mounted) return;
      setState(() {
        _basket = fresh;
        _quantity = math.min(_quantity, _maxQuantity);
      });
    } catch (_) {
      // Keep the current data; the inline error already explains the issue.
    }
  }

  // ------------------------------------------------------------------ UI

  String get _stepTitle => switch (_step) {
        ReserveStep.quantity => 'Quantité',
        ReserveStep.payment => 'Mode de paiement',
        ReserveStep.summary => 'Récapitulatif',
        ReserveStep.success => 'Réservation confirmée',
      };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : FoodSaveMotion.medium;
    return PopScope(
      canPop: !_submitting && _step != ReserveStep.success,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step != ReserveStep.success) _header(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md),
                  child: AnimatedSize(
                    duration: duration,
                    curve: FoodSaveMotion.curve,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: FoodSaveMotion.curve,
                      switchOutCurve: FoodSaveMotion.curve,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          ReserveStep.quantity => _quantityStep(context),
                          ReserveStep.payment => _paymentStep(context),
                          ReserveStep.summary => _summaryStep(context),
                          ReserveStep.success =>
                            _SuccessView(email: widget.session.user?.email),
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_step != ReserveStep.success) _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final index = _step.index + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _step == ReserveStep.quantity ? 'Fermer' : 'Retour',
                onPressed: _submitting ? null : _back,
                icon: Icon(_step == ReserveStep.quantity
                    ? Icons.close
                    : Icons.arrow_back),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_stepTitle, style: theme.textTheme.titleLarge),
                    Text('Étape $index sur 3',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryStrong)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Semantics(
              label: 'Étape $index sur 3',
              excludeSemantics: true,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: AnimatedContainer(
                        duration: FoodSaveMotion.medium,
                        curve: FoodSaveMotion.curve,
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < index
                              ? AppColors.moduleFoodSave
                              : AppColors.outlineSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final Widget button = switch (_step) {
      ReserveStep.quantity => FilledButton(
          style: foodSaveFilledStyle(),
          onPressed: _quantity >= 1 ? () => _goTo(ReserveStep.payment) : null,
          child: const Text('Continuer'),
        ),
      ReserveStep.payment => FilledButton(
          style: foodSaveFilledStyle(),
          onPressed: _selectedMethod != null
              ? () => _goTo(ReserveStep.summary)
              : null,
          child: const Text('Continuer'),
        ),
      ReserveStep.summary => FilledButton(
          key: const ValueKey('reserve-confirm'),
          style: foodSaveFilledStyle(),
          onPressed: _submitting ? null : _confirm,
          child: AnimatedSwitcher(
            duration: FoodSaveMotion.fast,
            child: _submitting
                ? const SizedBox.square(
                    key: ValueKey('loading'),
                    dimension: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text('Confirmer et payer ${MoneyText.format(_total)}',
                    key: const ValueKey('label')),
          ),
        ),
      ReserveStep.success => const SizedBox.shrink(),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: button,
    );
  }

  // ------------------------------------------------------------ step 1

  Widget _quantityStep(BuildContext context) {
    final theme = Theme.of(context);
    final store = _basket.commerce;
    final max = _maxQuantity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 64,
              child: BasketImage(
                  api: _api,
                  basket: _basket,
                  height: 64,
                  borderRadius: AppRadius.sm),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_basket.titre,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (store != null)
                    Text(store.nom,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondaryStrong)),
                  Text(
                    pickupWindowFr(
                        _basket.creneauRetraitDebut, _basket.creneauRetraitFin),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondaryStrong),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (max == 0)
          _InlineMessage(
            icon: Icons.inventory_2_outlined,
            color: AppColors.warning,
            message:
                'Panier épuisé : revenez plus tard, des unités peuvent être remises en vente.',
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Diminuer la quantité',
                iconSize: 28,
                constraints: const BoxConstraints.tightFor(width: 56, height: 56),
                onPressed:
                    _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 88,
                child: Semantics(
                  liveRegion: true,
                  label: 'Quantité : $_quantity',
                  excludeSemantics: true,
                  child: AnimatedSwitcher(
                    duration: FoodSaveMotion.fast,
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: Text(
                      '$_quantity',
                      key: ValueKey(_quantity),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Augmenter la quantité',
                iconSize: 28,
                constraints: const BoxConstraints.tightFor(width: 56, height: 56),
                onPressed: _quantity < max
                    ? () => setState(() => _quantity++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            max == 1
                ? 'Il reste 1 panier'
                : 'Jusqu\'à $max paniers par réservation',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondaryStrong),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.moduleFoodSaveSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child:
                            Text('Total', style: theme.textTheme.titleMedium)),
                    MoneyText(_total,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                if (_savings > 0) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Vous économisez',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.moduleFoodSaveDeep)),
                            MoneyText(_savings,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.moduleFoodSaveDeep,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      DiscountBadge(
                          prixCentimes: _basket.prixCentimes,
                          prixInitialCentimes: _basket.prixInitialCentimes),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ step 2

  Widget _paymentStep(BuildContext context) {
    final theme = Theme.of(context);
    final methods = _methods;
    if (_methodsLoading && methods == null) {
      return const Column(
        children: [
          SkeletonBox(height: 64, radius: AppRadius.md),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 64, radius: AppRadius.md),
        ],
      );
    }
    if (_methodsError != null && methods == null) {
      return FoodSaveErrorView(error: _methodsError, onRetry: _loadMethods);
    }
    if (methods == null || methods.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.moduleFoodSave.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.credit_card_off_outlined,
                color: AppColors.moduleFoodSaveDeep, size: 32),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Aucun moyen de paiement enregistré',
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Ajoutez une carte, votre portefeuille ou les espèces pour réserver ce panier.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondaryStrong),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.moduleFoodSaveDeep),
            onPressed: _addMethod,
            icon: const Icon(Icons.add_card),
            label: const Text('Ajouter un moyen de paiement'),
          ),
        ],
      );
    }
    final balance = widget.session.user?.soldeCentimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in methods) ...[
          PaymentMethodOption(
            key: ValueKey('payment-method-${m.id}'),
            method: m,
            selected: m.id == _selectedMethodId,
            walletBalanceCents: balance,
            amountCents: _total,
            onTap: () => setState(() => _selectedMethodId = m.id),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
                foregroundColor: AppColors.moduleFoodSaveDeep,
                minimumSize: const Size(48, 48)),
            onPressed: _addMethod,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un autre moyen'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ step 3

  Widget _summaryStep(BuildContext context) {
    final theme = Theme.of(context);
    final method = _selectedMethod;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(label: 'Panier', value: Text(_basket.titre)),
        if (_basket.commerce != null)
          _SummaryRow(label: 'Commerce', value: Text(_basket.commerce!.nom)),
        _SummaryRow(
          label: 'Retrait',
          value: Text(pickupWindowFr(
                  _basket.creneauRetraitDebut, _basket.creneauRetraitFin)
              .replaceFirst('Retrait ', '')),
        ),
        _SummaryRow(label: 'Quantité', value: Text(basketsCount(_quantity))),
        if (method != null)
          _SummaryRow(
              label: 'Mode de paiement', value: Text(paymentMethodTitle(method))),
        const Divider(height: AppSpacing.lg, color: AppColors.outlineSoft),
        _SummaryRow(
          label: 'Total',
          value: MoneyText(_total,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InlineMessage(
          icon: Icons.schedule,
          color: AppColors.warning,
          message: qrExpiryNote,
        ),
        AnimatedSize(
          duration: FoodSaveMotion.fast,
          curve: FoodSaveMotion.curve,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _ErrorPanel(
                    error: error,
                    onChangeMethod: () => _goTo(ReserveStep.payment),
                    onChangeQuantity: () => _goTo(ReserveStep.quantity),
                  ),
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- widgets

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryStrong)),
          ),
          Expanded(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tinted note with dark text (safe on warning / FoodSave tints).
class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.text),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.text)),
            ),
          ],
        ),
      );
}

/// Inline error with the corrective action matching the failure.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.error,
    required this.onChangeMethod,
    required this.onChangeQuantity,
  });

  final ApiException error;
  final VoidCallback onChangeMethod;
  final VoidCallback onChangeQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String hint, String? action, VoidCallback? onAction) =
        switch (error.statusCode) {
      402 => (
          'Aucun montant n\'a été débité. Choisissez un autre moyen de paiement puis réessayez.',
          'Changer de moyen de paiement',
          onChangeMethod,
        ),
      409 => (
          'La disponibilité de ce panier a changé. Ajustez la quantité ou choisissez un autre panier.',
          'Modifier la quantité',
          onChangeQuantity,
        ),
      _ => ('Vérifiez votre connexion puis réessayez.', null, null),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(FoodSaveErrorView.messageOf(error),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(hint,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.text)),
                    ],
                  ),
                ),
              ],
            ),
            if (action != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.moduleFoodSaveDeep,
                      minimumSize: const Size(48, 48)),
                  onPressed: onAction,
                  child: Text(action),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({this.email});

  /// Where the server e-mailed the QR code (shown when known).
  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Semantics(
        liveRegion: true,
        label: 'Réservation confirmée. Votre QR code est prêt.'
            '${email == null ? '' : ' Envoyé aussi par e-mail à $email.'}',
        excludeSemantics: true,
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 52),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Réservation confirmée !',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxs),
            Text('Votre QR code de retrait est prêt.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryStrong),
                textAlign: TextAlign.center),
            if (email != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.moduleFoodSaveSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.forward_to_inbox_outlined,
                        size: 18, color: AppColors.moduleFoodSaveDeep),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text('Envoyé aussi par e-mail à $email',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.text)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
