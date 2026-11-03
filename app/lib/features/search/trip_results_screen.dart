import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/empty_state.dart';
import '../reservations/reservation_api.dart';
import '../trips/trip_api.dart';
import 'trip_detail_screen.dart';
import 'trip_search_query.dart';
import 'widgets/trip_result_card.dart';

/// "Trajets disponibles": trips around the passenger, nearest departure time
/// first. Tapping a card opens the detail / booking screen.
class TripResultsScreen extends StatefulWidget {
  const TripResultsScreen({
    super.key,
    required this.session,
    required this.query,
  });

  final SessionController session;
  final TripSearchQuery query;

  @override
  State<TripResultsScreen> createState() => _TripResultsScreenState();
}

class _TripResultsScreenState extends State<TripResultsScreen> {
  late final TripApi _api = TripApi(widget.session.api);
  late Future<List<TripDto>> _future = _api.search(widget.query);

  Future<void> _reload() async {
    final next = _api.search(widget.query);
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _open(TripDto trip) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            TripDetailScreen(session: widget.session, trip: trip),
      ),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trajets disponibles')),
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
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Recherche impossible',
                    message: '${apiErrorMessage(snapshot.error!, fallback: 'Impossible de charger les trajets')}'
                        '\nTirez vers le bas pour réessayer.',
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
                    icon: Icons.search_off_outlined,
                    title: 'Aucun trajet trouvé',
                    message:
                        'Essayez un rayon plus grand, une autre date ou moins de filtres.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: trips.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Text(
                    '${trips.length} trajet(s) dans un rayon de '
                    '${widget.query.rayonKm.round()} km',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                }
                final trip = trips[i - 1];
                return TripResultCard(trip: trip, onTap: () => _open(trip));
              },
            );
          },
        ),
      ),
    );
  }
}
