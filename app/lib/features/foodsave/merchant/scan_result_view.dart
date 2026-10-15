import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../widgets/foodsave_ui.dart';

/// Visual recipe for one scan outcome.
class ScanOutcomeStyle {
  const ScanOutcomeStyle({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.title,
    required this.advice,
  });

  /// Circle fill.
  final Color color;

  /// Icon colour on [color] (dark on warning — contrast rule).
  final Color onColor;
  final IconData icon;
  final String title;

  /// What the merchant should do next.
  final String advice;

  static ScanOutcomeStyle of(ScanOutcome outcome) => switch (outcome) {
        ScanOutcome.accepte => const ScanOutcomeStyle(
            color: AppColors.success,
            onColor: Colors.white,
            icon: Icons.check_rounded,
            title: 'Retrait validé',
            advice: 'Remettez le panier au client.'),
        ScanOutcome.expire => const ScanOutcomeStyle(
            color: AppColors.warning,
            onColor: AppColors.text,
            icon: Icons.timer_off_outlined,
            title: 'QR code expiré',
            advice:
                'Ne remettez pas le panier. Les unités ont été remises en vente : le client peut effectuer une nouvelle réservation.'),
        ScanOutcome.dejaUtilise => const ScanOutcomeStyle(
            color: AppColors.warning,
            onColor: AppColors.text,
            icon: Icons.history,
            title: 'QR code déjà utilisé',
            advice:
                'Ce panier a déjà été remis. Ne le remettez pas une seconde fois.'),
        ScanOutcome.annule => const ScanOutcomeStyle(
            color: AppColors.error,
            onColor: Colors.white,
            icon: Icons.block,
            title: 'Réservation annulée',
            advice:
                'Ne remettez pas le panier : cette réservation a été annulée.'),
        ScanOutcome.invalide => const ScanOutcomeStyle(
            color: AppColors.error,
            onColor: Colors.white,
            icon: Icons.qr_code_2,
            title: 'QR code invalide',
            advice:
                'Demandez au client d\'ouvrir le QR code de sa réservation dans ProxiLife, puis scannez-le à nouveau.'),
        ScanOutcome.autreCommercant => const ScanOutcomeStyle(
            color: AppColors.error,
            onColor: Colors.white,
            icon: Icons.storefront_outlined,
            title: 'Réservation d\'un autre commerce',
            advice:
                'Cette réservation ne concerne pas votre commerce : indiquez au client le bon point de retrait.'),
        ScanOutcome.paiementNonConfirme => const ScanOutcomeStyle(
            color: AppColors.warning,
            onColor: AppColors.text,
            icon: Icons.credit_card_off_outlined,
            title: 'Paiement non confirmé',
            advice:
                'Ne remettez pas le panier tant que le paiement n\'est pas confirmé.'),
      };
}

/// Full-screen animated result of a scan (accepted or refused).
class ScanResultView extends StatefulWidget {
  const ScanResultView({
    super.key,
    required this.result,
    required this.onScanAgain,
    required this.onDone,
  });

  final ScanResultDto result;
  final VoidCallback onScanAgain;
  final VoidCallback onDone;

  @override
  State<ScanResultView> createState() => _ScanResultViewState();
}

class _ScanResultViewState extends State<ScanResultView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480));
  late final Animation<double> _circle = CurvedAnimation(
      parent: _c, curve: const Interval(0, 0.6, curve: FoodSaveMotion.curve));
  late final Animation<double> _icon = CurvedAnimation(
      parent: _c, curve: const Interval(0.35, 1, curve: Curves.easeOutBack));
  late final Animation<double> _body = CurvedAnimation(
      parent: _c, curve: const Interval(0.3, 1, curve: FoodSaveMotion.curve));

  @override
  void initState() {
    super.initState();
    // Best effort: no vibration support must never break the result screen.
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final style = ScanOutcomeStyle.of(result.resultat);
    final r = result.reservation;

    return ColoredBox(
      color: AppColors.background,
      child: Container(
        color: style.color.withValues(alpha: 0.08),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.xxl, AppSpacing.lg, AppSpacing.md),
                  children: [
                    Center(
                      child: ScaleTransition(
                        scale: _circle,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: style.color.withValues(alpha: 0.35),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ScaleTransition(
                            scale: _icon,
                            child: Icon(style.icon,
                                size: 68, color: style.onColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FadeTransition(
                      opacity: _body,
                      child: Column(
                        children: [
                          Semantics(
                            liveRegion: true,
                            header: true,
                            child: Text(style.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(result.message,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge),
                          const SizedBox(height: AppSpacing.lg),
                          if (result.accepte && r != null)
                            _Details(reservation: r)
                          else
                            _Advice(text: style.advice, color: style.color),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: Column(
                  children: [
                    FilledButton.icon(
                      style: foodSaveFilledStyle(),
                      onPressed: widget.onScanAgain,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scanner un autre code'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: const BorderSide(color: AppColors.outline),
                      ),
                      onPressed: widget.onDone,
                      child: const Text('Terminer'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.reservation});

  final ReservationDto reservation;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final rows = <(IconData, String, String)>[
      (Icons.person_outline, 'Client', r.clientNom ?? 'Client n° ${r.clientId}'),
      (
        Icons.shopping_basket_outlined,
        'Panier',
        r.panier?.titre ?? 'Panier n° ${r.panierId}'
      ),
      (Icons.inventory_2_outlined, 'Quantité', '× ${r.quantiteReservee}'),
      (Icons.payments_outlined, 'Montant payé', MoneyText.format(r.montantCentimes)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            for (final (icon, label, value) in rows)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: AppColors.success),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(label,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: AppColors.textSecondaryStrong)),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        flex: 2,
                        child: Text(value,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Advice extends StatelessWidget {
  const _Advice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 22, color: AppColors.textSecondaryStrong),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.text)),
            ),
          ],
        ),
      );
}
