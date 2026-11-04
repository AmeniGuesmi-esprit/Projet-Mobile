import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../trips/trip_labels.dart';
import 'reservation_api.dart';
import 'widgets/reservation_status_badge.dart';

/// "Demandes reçues" (driver): seat requests on his trips, with Accepter /
/// Refuser on the pending ones.
class ReceivedRequestsScreen extends StatefulWidget {
  const ReceivedRequestsScreen({super.key, required this.session, this.embedded = false});

  final SessionController session;

  /// Shown inside [CovoiturageHubScreen] (no own app bar).
  final bool embedded;

  @override
  State<ReceivedRequestsScreen> createState() => _ReceivedRequestsScreenState();
}

class _ReceivedRequestsScreenState extends State<ReceivedRequestsScreen> {
  late final ReservationApi _api = ReservationApi(widget.session.api);
  late Future<List<TripReservationDto>> _future = _api.received();
  final Set<int> _busy = {};

  Future<void> _reload() async {
    final next = _api.received();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _decide(TripReservationDto r, {required bool accept}) async {
    if (!accept) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Refuser cette demande ?'),
          content: Text('${r.passagerNom} sera informé(e) du refus.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Oui, refuser'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy.add(r.id));
    try {
      if (accept) {
        await _api.accept(r.id);
      } else {
        await _api.refuse(r.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Demande acceptée' : 'Demande refusée'),
      ));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        await _reload();
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Inside the "Covoiturage" hub, its tab bar replaces this one.
      appBar: widget.embedded
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Demandes reçues'),
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
                        '${apiErrorMessage(snapshot.error!, fallback: 'Impossible de charger les demandes')}'
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
                    icon: Icons.inbox_outlined,
                    title: 'Aucune demande',
                    message:
                        'Les demandes de places sur vos trajets apparaîtront ici.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _RequestCard(
                reservation: items[i],
                busy: _busy.contains(items[i].id),
                onAccept: () => _decide(items[i], accept: true),
                onRefuse: () => _decide(items[i], accept: false),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.reservation,
    required this.busy,
    required this.onAccept,
    required this.onRefuse,
  });

  final TripReservationDto reservation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = reservation.trajet;
    final when = trip.dateHeureDepart;
    final pending = reservation.statut == TripReservationStatus.enAttente;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: pending ? AppColors.warning : AppColors.outlineSoft,
          width: pending ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${trip.departAdresse} → ${trip.arriveeAdresse}',
            style: theme.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('${formatTripDate(when)} · ${formatTripTime(when)}',
              style: theme.textTheme.bodyMedium),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  reservation.passagerNom.isEmpty
                      ? '?'
                      : reservation.passagerNom.substring(0, 1).toUpperCase(),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.primaryDeep),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reservation.passagerNom,
                        style: theme.textTheme.titleMedium),
                    Text(
                      '${reservation.nbPlaces} place(s) · ${MoneyText.format(reservation.montantCentimes)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              ReservationStatusBadge(reservation.statut),
            ],
          ),
          if (reservation.estEmbarque) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.success),
                const SizedBox(width: AppSpacing.xxs),
                Text('Embarqué',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.success)),
              ],
            ),
          ],
          if (pending) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onRefuse,
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
