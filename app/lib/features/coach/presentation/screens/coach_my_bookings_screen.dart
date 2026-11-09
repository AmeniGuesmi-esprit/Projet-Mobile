import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/live/live_refresh.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';
import 'coach_booking_detail_screen.dart';

enum _Bucket { upcoming, past, cancelled }

/// Where a booking is listed: à venir / passées / annulées.
_Bucket _bucketOf(CoachBookingDto b, DateTime now) {
  if (b.statut == CoachBookingStatus.annulee) return _Bucket.cancelled;
  if (b.statut == CoachBookingStatus.present) return _Bucket.past;
  final s = b.seance;
  if (s != null && s.isCancelled) return _Bucket.cancelled;
  if (s != null && !s.fin.isAfter(now)) return _Bucket.past;
  return _Bucket.upcoming;
}

/// Client: « Mes réservations » (à venir, passées, annulées), kept up to date
/// by [LiveRefresh] (e.g. the status turns « Présent » once the coach scanned
/// the QR code).
class CoachMyBookingsScreen extends StatefulWidget {
  const CoachMyBookingsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CoachMyBookingsScreen> createState() => _CoachMyBookingsScreenState();
}

class _CoachMyBookingsScreenState extends State<CoachMyBookingsScreen>
    with LiveRefresh<CoachMyBookingsScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late Future<List<CoachBookingDto>> _future = _api.myBookings();

  @override
  Future<void> liveRefresh() async {
    final items = await _api.myBookings();
    if (!mounted) return;
    setState(() {
      _future = liveFuture(items);
    });
  }

  void _reload() => setState(() {
        _future = _api.myBookings();
      });

  Future<void> _open(CoachBookingDto b) async {
    await pushCoach<void>(
      context,
      CoachBookingDetailScreen(session: widget.session, bookingId: b.id),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return CoachAsyncView<List<CoachBookingDto>>(
      future: _future,
      onRetry: _reload,
      builder: (context, bookings) {
        final now = DateTime.now();
        List<CoachBookingDto> of(_Bucket bucket) => bookings
            .where((b) => _bucketOf(b, now) == bucket)
            .toList();
        final upcoming = of(_Bucket.upcoming)
          ..sort((a, b) => (a.seance?.dateHeure ?? a.creeLe)
              .compareTo(b.seance?.dateHeure ?? b.creeLe));
        final past = of(_Bucket.past);
        final cancelled = of(_Bucket.cancelled);
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'À venir (${upcoming.length})'),
                  Tab(text: 'Passées (${past.length})'),
                  Tab(text: 'Annulées (${cancelled.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _BookingList(
                      bookings: upcoming,
                      emptyTitle: 'Aucune séance à venir',
                      emptyMessage:
                          'Réservez une séance depuis l\'onglet « Séances ».',
                      onOpen: _open,
                      onRefresh: () async {
                        _reload();
                        await _future.catchError((_) => <CoachBookingDto>[]);
                      },
                    ),
                    _BookingList(
                      bookings: past,
                      emptyTitle: 'Aucune séance passée',
                      emptyMessage:
                          'Vos séances terminées apparaîtront ici.',
                      onOpen: _open,
                      onRefresh: () async {
                        _reload();
                        await _future.catchError((_) => <CoachBookingDto>[]);
                      },
                    ),
                    _BookingList(
                      bookings: cancelled,
                      emptyTitle: 'Aucune réservation annulée',
                      emptyMessage: 'Les réservations annulées apparaîtront ici.',
                      onOpen: _open,
                      onRefresh: () async {
                        _reload();
                        await _future.catchError((_) => <CoachBookingDto>[]);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<CoachBookingDto> bookings;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<CoachBookingDto> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: CoachColors.brandDeep,
      onRefresh: onRefresh,
      child: bookings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: AppSpacing.xl),
                EmptyState(
                  icon: Icons.event_available_outlined,
                  title: emptyTitle,
                  message: emptyMessage,
                  color: AppColors.moduleCoachProche,
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: bookings.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _BookingCard(
                booking: bookings[i],
                onTap: () => onOpen(bookings[i]),
              ),
            ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});

  final CoachBookingDto booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = booking.seance;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (s != null) ...[
                    CoachTypeAvatar(s.type),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s?.titre ?? 'Séance n°${booking.seanceId}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        if (s != null)
                          Text('${coachWhen(s.dateHeure)} · '
                              '${coachDuration(s.dureeMinutes)}',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  CoachBookingStatusChip(booking.statut),
                ],
              ),
              if (s != null) ...[
                const SizedBox(height: AppSpacing.xs),
                CoachInfoRow(icon: Icons.place_outlined, text: s.lieu),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    coachPrice(booking.montantCentimes),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: CoachColors.brandDeep,
                    ),
                  ),
                  const Spacer(),
                  if (booking.statut.isActive && booking.hasQr) ...[
                    const Icon(Icons.qr_code_2,
                        size: 18, color: CoachColors.brandDeep),
                    const SizedBox(width: 4),
                    Text('Afficher mon QR code',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: CoachColors.brandDeep)),
                  ] else if (booking.statut == CoachBookingStatus.present &&
                      booking.pas == null &&
                      booking.frequenceCardiaque == null)
                    Text('Ajouter mon suivi',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: CoachColors.brandDeep)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
