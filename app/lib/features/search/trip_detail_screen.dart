import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart';
import '../trips/trip_labels.dart';
import '../trips/widgets/trip_preference_chips.dart';
import 'widgets/trip_result_card.dart';

/// "Détail du trajet" (passenger): driver, route, preferences, seats and the
/// "Réserver" button. Pops `true` when a request was sent.
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.session,
    required this.trip,
  });

  final SessionController session;
  final TripDto trip;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late final ReservationApi _api = ReservationApi(widget.session.api);

  int _places = 1;
  TripReservationDto? _existing;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  /// Is there already a pending / accepted request of mine on this trip?
  Future<void> _loadExisting() async {
    try {
      final list = await _api.mine();
      if (!mounted) return;
      TripReservationDto? found;
      for (final r in list) {
        if (r.trajet.id == widget.trip.id && r.statut.isActive) found = r;
      }
      setState(() => _existing = found);
    } catch (_) {
      // Not blocking: the server also refuses duplicates.
    }
  }

  Future<void> _reserve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.request(tripId: widget.trip.id, nbPlaces: _places);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 36),
          title: const Text('Demande envoyée'),
          content: const Text(
            'Le conducteur va examiner votre demande. Vous pouvez la suivre '
            'dans l\'onglet « Réservations ».',
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
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Une erreur est survenue, veuillez réessayer');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = widget.trip;
    final when = trip.dateHeureDepart;
    final maxPlaces = trip.placesDisponibles.clamp(1, TripRules.maxSeats);
    final total = _places * trip.prixParPlaceCentimes;
    final existing = _existing;
    final distance = trip.distanceDepartKm;

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du trajet')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Panel(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(initialOf(trip.conducteurNom),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: AppColors.primaryDeep)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trip.conducteurNom,
                            style: theme.textTheme.titleMedium),
                        Text(
                          trip.noteMoyenne == null
                              ? 'Pas encore d\'avis'
                              : '★ ${trip.noteMoyenne!.toStringAsFixed(1)} · ${trip.nbAvis} avis',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Stop(
                    icon: Icons.trip_origin,
                    color: AppColors.primary,
                    text: trip.departAdresse,
                    trailing: formatTripTime(when),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: Container(
                        width: 2, height: 16, color: AppColors.outline),
                  ),
                  _Stop(
                    icon: Icons.flag_outlined,
                    color: AppColors.accent,
                    text: trip.arriveeAdresse,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${formatTripDate(when)}'
                    '${distance == null ? '' : ' · départ à ${formatKm(distance)} de vous'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Préférences de voyage',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  TripPreferenceChips(trip),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Véhicule : ${trip.vehicule.marque} ${trip.vehicule.modele} · ${trip.vehicule.couleur}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (existing != null)
              _Panel(
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        existing.statut == TripReservationStatus.acceptee
                            ? 'Votre réservation est confirmée (${existing.nbPlaces} place(s)).'
                            : 'Votre demande (${existing.nbPlaces} place(s)) attend la réponse du conducteur.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _Panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Places',
                              style: theme.textTheme.titleMedium),
                        ),
                        IconButton(
                          tooltip: 'Moins',
                          onPressed: _places > 1
                              ? () => setState(() => _places--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_places', style: theme.textTheme.titleLarge),
                        IconButton(
                          tooltip: 'Plus',
                          onPressed: _places < maxPlaces
                              ? () => setState(() => _places++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${trip.placesDisponibles} place(s) disponible(s) · '
                            '${MoneyText.format(trip.prixParPlaceCentimes)} / place',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                            child: Text('Total',
                                style: theme.textTheme.titleMedium)),
                        Text(
                          MoneyText.format(total),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: AppColors.primaryDeep),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
              PrimaryButton(
                label: 'Demander $_places place(s)',
                icon: Icons.event_seat_outlined,
                isLoading: _loading,
                onPressed: _reserve,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Le conducteur doit accepter votre demande. Le paiement se fera plus tard.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: child,
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.icon,
    required this.color,
    required this.text,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        if (trailing != null)
          Text(trailing!, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
