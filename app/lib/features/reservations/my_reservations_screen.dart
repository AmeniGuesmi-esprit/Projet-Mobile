import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../boarding/boarding_rules.dart';
import '../boarding/passenger_boarding_screen.dart';
import '../trips/trip_labels.dart';
import 'reservation_api.dart';
import 'widgets/reservation_status_badge.dart';

/// "Mes réservations" (passenger): requests sent, their status, cancellation.
class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  late final ReservationApi _api = ReservationApi(widget.session.api);
  late Future<List<TripReservationDto>> _future = _api.mine();
  final Set<int> _busy = {};

  Future<void> _reload() async {
    final next = _api.mine();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _board(TripReservationDto r) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PassengerBoardingScreen(
          session: widget.session,
          reservation: r,
        ),
      ),
    );
    if (done == true) await _reload();
  }

  Future<void> _cancel(TripReservationDto r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler cette réservation ?'),
        content: Text(r.statut == TripReservationStatus.acceptee
            ? 'Votre place sera libérée pour les autres passagers.'
            : 'Votre demande sera retirée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy.add(r.id));
    try {
      await _api.cancel(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Réservation annulée')));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Mes réservations'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reload,
        child: FutureBuilder<List<TripReservationDto>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Chargement impossible',
                    message:
                        '${apiErrorMessage(snapshot.error!, fallback: 'Impossible de charger vos réservations')}'
                        '\nTirez vers le bas pour réessayer.',
                    color: AppColors.error,
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <TripReservationDto>[];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.event_seat_outlined,
                    title: 'Aucune réservation',
                    message:
                        'Recherchez un trajet près de chez vous pour demander une place.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _ReservationCard(
                reservation: items[i],
                busy: _busy.contains(items[i].id),
                onCancel: () => _cancel(items[i]),
                onBoard: () => _board(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.busy,
    required this.onCancel,
    required this.onBoard,
  });

  final TripReservationDto reservation;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onBoard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = reservation.trajet;
    final when = trip.dateHeureDepart;
    final canCancel =
        reservation.statut.isActive && when.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${trip.departAdresse} → ${trip.arriveeAdresse}',
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ReservationStatusBadge(reservation.statut),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatTripDate(when)} · ${formatTripTime(when)} · avec ${trip.conducteurNom}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.event_seat_outlined,
                  size: 18, color: AppColors.textSecondaryStrong),
              const SizedBox(width: AppSpacing.xxs),
              Text('${reservation.nbPlaces} place(s)',
                  style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(MoneyText.format(reservation.montantCentimes),
                  style: theme.textTheme.titleMedium),
            ],
          ),
          if (reservation.estEmbarque)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Embarquement confirmé',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.success)),
                ],
              ),
            )
          else if (reservation.statut == TripReservationStatus.acceptee &&
              isBoardingWindowOpen(when))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onBoard,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Je suis monté'),
                ),
              ),
            ),
          if (canCancel && !reservation.estEmbarque)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close, size: 18),
                label: const Text('Annuler'),
              ),
            ),
        ],
      ),
    );
  }
}
