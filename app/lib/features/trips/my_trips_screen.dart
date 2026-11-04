import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/money_text.dart';
import '../boarding/boarding_rules.dart';
import '../boarding/driver_boarding_screen.dart';
import 'publish_trip_screen.dart';
import 'trip_api.dart';
import 'trip_labels.dart';
import 'widgets/trip_preference_chips.dart';

/// Trips published by the connected driver.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key, required this.session, this.embedded = false});

  final SessionController session;

  /// Shown inside [CovoiturageHubScreen] (no own app bar).
  final bool embedded;

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  late final TripApi _api = TripApi(widget.session.api);
  late Future<List<TripDto>> _future = _api.myTrips();

  Future<void> _reload() async {
    final next = _api.myTrips();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _publish() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PublishTripScreen(session: widget.session),
      ),
    );
    if (published == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Inside the "Covoiturage" hub, its tab bar replaces this one.
      appBar: widget.embedded
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Mes trajets'),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'tripsFab',
        onPressed: _publish,
        icon: const Icon(Icons.add),
        label: const Text('Publier'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reload,
        child: FutureBuilder<List<TripDto>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is ApiException
                  ? error.message
                  : 'Impossible de charger vos trajets';
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Chargement impossible',
                    message: '$message\nTirez vers le bas pour réessayer.',
                    color: AppColors.error,
                  ),
                ],
              );
            }
            final trips = snapshot.data ?? const <TripDto>[];
            if (trips.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.directions_car_outlined,
                    title: 'Aucun trajet publié',
                    message: 'Appuyez sur « Publier » pour proposer un trajet.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                96,
              ),
              itemCount: trips.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _TripCard(
                trip: trips[i],
                onBoarding: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DriverBoardingScreen(
                      session: widget.session,
                      trip: trips[i],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onBoarding});

  final TripDto trip;
  final VoidCallback onBoarding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = trip.dateHeureDepart;
    final active = trip.statut == TripStatus.ouvert;
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
              Text(
                trip.statut.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: active ? AppColors.success : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatTripDate(when)} · ${formatTripTime(when)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.event_seat_outlined,
                  size: 18, color: AppColors.textSecondaryStrong),
              const SizedBox(width: AppSpacing.xxs),
              Text('${trip.placesDisponibles}/${trip.placesTotales} place(s)',
                  style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                MoneyText.format(trip.prixParPlaceCentimes),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TripPreferenceChips(trip),
          if ((active || trip.statut == TripStatus.complet) &&
              isBoardingWindowOpen(when))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onBoarding,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Ouvrir l\'embarquement'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
