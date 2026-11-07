import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/live/live_refresh.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_tracking_card.dart';
import '../widgets/coach_widgets.dart';

/// Client: one booking — the QR code to show to the coach, the payment, the
/// cancellation and, once the presence is validated, the tracking (steps,
/// BPM). Polls the server (every 10 s) to notice the presence validation.
class CoachBookingDetailScreen extends StatefulWidget {
  const CoachBookingDetailScreen({
    super.key,
    required this.session,
    required this.bookingId,
    this.justBooked = false,
  });

  final SessionController session;
  final int bookingId;

  /// Shows the « Réservation confirmée » banner (right after booking).
  final bool justBooked;

  @override
  State<CoachBookingDetailScreen> createState() =>
      _CoachBookingDetailScreenState();
}

class _CoachBookingDetailScreenState extends State<CoachBookingDetailScreen>
    with LiveRefresh<CoachBookingDetailScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);

  CoachBookingDto? _booking;
  Object? _error;
  bool _loading = true;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await _api.getBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Future<void> liveRefresh() async {
    final fresh = await _api.getBooking(widget.bookingId);
    if (!mounted) return;
    final old = _booking;
    setState(() => _booking = fresh);
    if (old != null &&
        old.statut != CoachBookingStatus.present &&
        fresh.statut == CoachBookingStatus.present) {
      showCoachSnack(context, 'Présence validée par le coach. Bonne séance !');
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.event_busy_outlined, color: AppColors.error),
        title: const Text('Annuler cette réservation ?'),
        content: const Text(
          'Votre place sera libérée pour les autres participants. Si vous '
          'aviez déjà payé, vous serez remboursé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(120, 48),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annuler la réservation'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final cancelled = await _api.cancelBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = cancelled;
        _cancelling = false;
      });
      unawaited(widget.session.refreshUser()); // refund shows in the balance
      showCoachSnack(context, 'Réservation annulée, votre place est libérée');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      showCoachSnack(context, coachErrorMessage(e),
          actionLabel: 'Réessayer', onAction: _cancel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma réservation')),
      body: _loading && booking == null
          ? const Center(child: CircularProgressIndicator())
          : booking == null
              ? CoachErrorRetry(
                  message: coachErrorMessage(_error ?? 'Erreur'),
                  onRetry: _load,
                )
              : _content(context, booking),
    );
  }

  Widget _content(BuildContext context, CoachBookingDto b) {
    final theme = Theme.of(context);
    final s = b.seance;
    final canCancel = b.statut.isActive &&
        s != null &&
        !s.isCancelled &&
        s.dateHeure.isAfter(DateTime.now());
    return RefreshIndicator(
      color: CoachColors.brandDeep,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (widget.justBooked && b.statut.isActive)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Réservation confirmée ! Présentez le QR code ci-dessous '
                      'au coach.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              CoachBookingStatusChip(b.statut),
              const Spacer(),
              Text('Réservation n°${b.id}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _qrSection(context, b),
          if (s != null) ...[
            const CoachSectionTitle('La séance'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CoachTypeAvatar(s.type),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(s.titre,
                              style: theme.textTheme.titleMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    CoachInfoRow(
                      icon: Icons.event_outlined,
                      text: '${coachDay(s.dateHeure)} · '
                          '${coachRange(s.dateHeure, s.dureeMinutes)}',
                      strong: true,
                    ),
                    CoachInfoRow(icon: Icons.place_outlined, text: s.lieu),
                    CoachInfoRow(
                        icon: Icons.person_outline, text: 'Coach ${s.coachNom}'),
                    if (s.isCancelled)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Cette séance a été annulée par le coach.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const CoachSectionTitle('Paiement'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Montant', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        coachPrice(b.montantCentimes),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  if (b.modePaiement != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text('Mode', style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        Text(_modeLabel(b.modePaiement!),
                            style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ],
                  if (b.statutPaiement != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text('Statut', style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        StatusChip(b.statutPaiement!),
                      ],
                    ),
                  ],
                  if (b.factureNumero != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text('Facture', style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        Text(b.factureNumero!,
                            style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ],
                  if (b.modePaiement == PaymentMethodType.especes &&
                      b.statutPaiement == TransactionStatus.enAttente &&
                      b.statut.isActive)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'À régler en espèces au coach le jour de la séance : '
                        'le paiement est confirmé quand il scanne votre QR code.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (b.montantCentimes == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text('Séance gratuite : aucun paiement.',
                          style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ),
          if (b.statut == CoachBookingStatus.present) ...[
            const CoachSectionTitle('Suivi de la séance'),
            CoachTrackingCard(
              booking: b,
              api: _api,
              onSaved: (saved) => setState(() => _booking = saved),
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1.4),
              ),
              onPressed: _cancelling ? null : _cancel,
              icon: _cancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.event_busy_outlined),
              label: const Text('Annuler ma réservation'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _qrSection(BuildContext context, CoachBookingDto b) {
    final theme = Theme.of(context);
    if (b.statut.isActive && b.hasQr) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Semantics(
                label: 'QR code de présence à montrer au coach',
                image: true,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: QrImageView(
                    data: b.codeQr!,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Mon QR code de présence',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Montrez-le au coach à votre arrivée. Il peut être scanné '
                '${CoachRules.scanOpensBefore.inMinutes} minutes avant le '
                'début jusqu\'à la fin de la séance, une seule fois.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: b.codeQr!));
                  if (context.mounted) {
                    showCoachSnack(context, 'Code copié');
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copier le code (si la caméra ne marche pas)'),
              ),
            ],
          ),
        ),
      );
    }
    final (IconData icon, Color color, String title, String message) =
        switch (b.statut) {
      CoachBookingStatus.present => (
          Icons.how_to_reg_outlined,
          CoachColors.brandDeep,
          'Présence validée',
          b.presentLe == null
              ? 'Le coach a validé votre présence.'
              : 'Validée à ${coachClock(b.presentLe!)} : bonne séance !',
        ),
      CoachBookingStatus.annulee => (
          Icons.event_busy_outlined,
          AppColors.error,
          'Réservation annulée',
          'Cette réservation n\'est plus valable.',
        ),
      _ => (
          Icons.qr_code_2,
          AppColors.textSecondaryStrong,
          'QR code indisponible',
          'Tirez pour actualiser la page.',
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(icon, size: 44, color: color),
            const SizedBox(height: AppSpacing.xs),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(PaymentMethodType type) => switch (type) {
      PaymentMethodType.carteBancaire => 'Carte bancaire',
      PaymentMethodType.portefeuille => 'Portefeuille ProxiLife',
      PaymentMethodType.especes => 'Espèces',
    };
