import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'booking/booking_format.dart';
import 'booking/qr_panels.dart';
import 'widgets/client_format.dart';

/// Pickup QR code of one reservation, with a live countdown. Polls the
/// server while active to detect the pickup ("retire").
class ReservationQrScreen extends StatefulWidget {
  const ReservationQrScreen({
    super.key,
    required this.session,
    required this.reservationId,
    this.clock = systemClock,
    this.pollInterval = const Duration(seconds: 15),
  });

  final SessionController session;
  final int reservationId;

  /// Injectable time source (tests).
  final BookingClock clock;
  final Duration pollInterval;

  @override
  State<ReservationQrScreen> createState() => _ReservationQrScreenState();
}

class _ReservationQrScreenState extends State<ReservationQrScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late final ValueNotifier<DateTime> _now = ValueNotifier(widget.clock());
  Timer? _ticker;

  ReservationDto? _reservation;
  BasketDto? _basket;
  Object? _loadError;
  bool _loading = true;
  bool _fetching = false;
  bool _cancelling = false;
  bool _expiryRefetched = false;
  QrPhase? _phase;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _load();
    // One timer drives both the countdown and the 15 s polling.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _now.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_fetching) return;
    _fetching = true;
    _lastPoll = widget.clock();
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final r = await _api.getReservation(widget.reservationId);
      if (!mounted) return;
      setState(() => _apply(r));
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        developer.log('Reservation refresh failed: $e', name: 'foodsave');
      } else {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  void _apply(ReservationDto r) {
    _reservation = r;
    _basket = r.panier ?? _basket;
    _loading = false;
    _loadError = null;
    _phase = qrPhaseOf(r, _now.value);
  }

  void _tick() {
    final now = widget.clock();
    _now.value = now;
    final r = _reservation;
    if (r == null) return;
    final phase = qrPhaseOf(r, now);
    if (phase != _phase) setState(() => _phase = phase);
    if (phase == QrPhase.expired &&
        r.statut == ReservationStatus.enAttente &&
        !_expiryRefetched) {
      // Countdown reached zero: the server expires it lazily on GET.
      _expiryRefetched = true;
      _load(silent: true);
      return;
    }
    final watching = phase == QrPhase.active || phase == QrPhase.awaitingPayment;
    if (watching && now.difference(_lastPoll) >= widget.pollInterval) {
      _load(silent: true);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la réservation ?'),
        content: const Text(
            'Le panier sera remis en vente. Si vous avez payé, le montant vous sera remboursé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Garder'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler la réservation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final r = await _api.cancelReservation(widget.reservationId);
      if (!mounted) return;
      setState(() {
        _apply(r);
        _cancelling = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(r.statutPaiement == TransactionStatus.rembourse
              ? 'Réservation annulée : vous avez été remboursé.'
              : 'Réservation annulée.'),
        ));
      unawaited(widget.session.refreshUser().catchError((Object e) {
        developer.log('Balance refresh failed: $e', name: 'foodsave');
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      showFoodSaveError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget body;
    final r = _reservation;
    if (_loading && r == null) {
      body = const _QrSkeleton(key: ValueKey('loading'));
    } else if (r == null) {
      body = FoodSaveErrorView(
          key: const ValueKey('error'), error: _loadError, onRetry: _load);
    } else {
      body = _content(context, r);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('QR code de retrait')),
      body: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : FoodSaveMotion.medium,
        switchInCurve: FoodSaveMotion.curve,
        child: body,
      ),
    );
  }

  Widget _content(BuildContext context, ReservationDto r) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final phase = _phase ?? qrPhaseOf(r, _now.value);
    final basket = _basket;
    final store = basket?.commerce;
    final token = r.qrToken;
    final Widget panel = phase == QrPhase.active && token != null
        ? ActiveQrPanel(
            key: const ValueKey('qr-active'),
            reservation: r,
            token: token,
            now: _now,
          )
        : QrStatePanel(key: ValueKey(phase), phase: phase, reservation: r);

    return RefreshIndicator(
      key: const ValueKey('content'),
      color: AppColors.moduleFoodSaveDeep,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
        children: [
          Text(basket?.titre ?? 'Panier anti-gaspillage',
              style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (store != null)
                Text(store.nom,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.moduleFoodSaveDeep)),
              Text(reservationRef(r.id),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryStrong,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            switchOutCurve: FoodSaveMotion.curve,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
            ),
            child: panel,
          ),
          const SizedBox(height: AppSpacing.md),
          _DetailsCard(reservation: r, basket: basket),
          if (r.statut == ReservationStatus.enAttente &&
              phase != QrPhase.expired) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _cancelling ? null : _cancel,
              icon: _cancelling
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.close),
              label: const Text('Annuler la réservation'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.reservation, required this.basket});

  final ReservationDto reservation;
  final BasketDto? basket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reservation;
    final b = basket;
    final store = b?.commerce;
    final mode = r.modePaiement;
    Widget row(IconData icon, String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.moduleFoodSaveDeep),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryStrong)),
                    DefaultTextStyle.merge(
                        style: theme.textTheme.bodyLarge, child: value),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (store != null)
            row(Icons.storefront_outlined, 'Commerce',
                Text('${store.nom}\n${store.adresse}')),
          if (b != null)
            row(
                Icons.schedule,
                'Créneau de retrait',
                Text(pickupWindowFr(b.creneauRetraitDebut, b.creneauRetraitFin)
                    .replaceFirst('Retrait ', ''))),
          row(Icons.shopping_basket_outlined, 'Quantité',
              Text(basketsCount(r.quantiteReservee))),
          row(Icons.receipt_long_outlined, 'Montant',
              MoneyText(r.montantCentimes,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              ReservationStatusChip(r.statut),
              StatusChip(r.statutPaiement),
              if (mode != null)
                Chip(
                  avatar: Icon(paymentTypeIcon(mode),
                      size: 16, color: AppColors.textSecondaryStrong),
                  label: Text(paymentTypeLabel(mode)),
                  labelStyle: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryStrong),
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: AppColors.outline),
                  backgroundColor: AppColors.surface,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrSkeleton extends StatelessWidget {
  const _QrSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 28, width: 220),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 18, width: 160),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 360, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 180, radius: AppRadius.lg),
        ],
      );
}
