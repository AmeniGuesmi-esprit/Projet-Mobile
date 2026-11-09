import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';
import 'coach_booking_detail_screen.dart';
import 'coach_reserve_sheet.dart';

/// Client: detail of one session, with the « Réserver » action.
class CoachSessionDetailScreen extends StatefulWidget {
  const CoachSessionDetailScreen({
    super.key,
    required this.session,
    required this.initial,
  });

  final SessionController session;

  /// The session as shown in the list (displayed at once, refreshed below).
  final CoachSessionDto initial;

  @override
  State<CoachSessionDetailScreen> createState() =>
      _CoachSessionDetailScreenState();
}

class _CoachSessionDetailScreenState extends State<CoachSessionDetailScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late CoachSessionDto _s = widget.initial;

  /// Only the search endpoint computes the distance: keep it from the list.
  late final double? _distanceKm = widget.initial.distanceKm;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final fresh = await _api.getSession(widget.initial.id);
      if (mounted) setState(() => _s = fresh);
    } catch (_) {
      // Keep what is on screen (offline): the action buttons re-check on tap.
    }
  }

  Future<void> _openDirections() async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${_s.latitude},${_s.longitude}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      showCoachSnack(context, 'Impossible d\'ouvrir l\'itinéraire');
    }
  }

  Future<void> _reserve() async {
    final booking = await showModalBottomSheet<CoachBookingDto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CoachReserveSheet(
        session: widget.session,
        coachSession: _s,
      ),
    );
    if (booking == null || !mounted) return;
    unawaited(widget.session.refreshUser()); // new balance
    await Navigator.of(context).pushReplacement(
      CoachPageRoute<void>(
        builder: (_) => CoachBookingDetailScreen(
          session: widget.session,
          bookingId: booking.id,
          justBooked: true,
        ),
      ),
    );
  }

  Future<void> _openMyBooking() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bookings = await _api.myBookings();
      CoachBookingDto? mine;
      for (final b in bookings) {
        if (b.seanceId == _s.id && b.statut.isActive) mine = b;
      }
      if (!mounted) return;
      if (mine == null) {
        showCoachSnack(context, 'Réservation introuvable');
        await _refresh();
      } else {
        await pushCoach<void>(
          context,
          CoachBookingDetailScreen(
              session: widget.session, bookingId: mine.id),
        );
        await _refresh();
      }
    } catch (e) {
      if (mounted) showCoachSnack(context, coachErrorMessage(e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _notice(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.outlineSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondaryStrong),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _action() {
    final s = _s;
    if (s.isCancelled) {
      return _notice('Cette séance a été annulée par le coach.',
          Icons.cancel_outlined);
    }
    if (!s.dateHeure.isAfter(DateTime.now())) {
      return _notice('Cette séance a déjà commencé.', Icons.schedule);
    }
    if (s.coachId == widget.session.user?.id) {
      return _notice('Ceci est votre séance : gérez-la depuis « Mes séances ».',
          Icons.info_outline);
    }
    if (s.dejaReserve) {
      return FilledButton.icon(
        onPressed: _opening ? null : _openMyBooking,
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Voir ma réservation'),
      );
    }
    if (s.isFull) {
      return _notice('Cette séance est complète.', Icons.group_off_outlined);
    }
    return FilledButton(
      onPressed: _reserve,
      child: Text(s.isFree
          ? 'Réserver gratuitement'
          : 'Réserver · ${coachPrice(s.prixCentimes)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _s;
    final distance = _distanceKm;
    final fill = s.placesTotales == 0 ? 0.0 : s.inscrits / s.placesTotales;
    return Scaffold(
      appBar: AppBar(title: const Text('Séance')),
      body: RefreshIndicator(
        color: CoachColors.brandDeep,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: CoachColors.brandSoft,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CoachTypeAvatar(s.type, size: 56),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(s.titre,
                            style: theme.textTheme.titleLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      CoachChip(
                        label: s.type.label,
                        color: CoachColors.brandDeep,
                        icon: coachTypeIcon(s.type),
                      ),
                      CoachLevelChip(s.niveau),
                      if (s.isCancelled)
                        const CoachChip(
                            label: 'Annulée',
                            color: AppColors.error,
                            icon: Icons.cancel_outlined),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    coachPrice(s.prixCentimes),
                    style: theme.textTheme.displaySmall
                        ?.copyWith(color: CoachColors.brandDeep),
                  ),
                  Text('par participant', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const CoachSectionTitle('Quand et où'),
            CoachInfoRow(
              icon: Icons.event_outlined,
              text: '${coachDay(s.dateHeure)} · '
                  '${coachRange(s.dateHeure, s.dureeMinutes)} '
                  '(${coachDuration(s.dureeMinutes)})',
              strong: true,
            ),
            CoachInfoRow(
              icon: Icons.place_outlined,
              text: distance == null
                  ? s.lieu
                  : '${s.lieu} · à ${coachDistance(distance)} de vous',
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48)),
                onPressed: _openDirections,
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Itinéraire'),
              ),
            ),
            const CoachSectionTitle('Coach'),
            CoachInfoRow(icon: Icons.person_outline, text: s.coachNom),
            const CoachSectionTitle('Places'),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 8,
                color: CoachColors.brand,
                backgroundColor: CoachColors.brandSoft,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${s.inscrits} inscrit${s.inscrits > 1 ? 's' : ''} sur '
              '${s.placesTotales} · ${coachPlaces(s)}',
              style: theme.textTheme.bodyMedium,
            ),
            if ((s.description ?? '').trim().isNotEmpty) ...[
              const CoachSectionTitle('Description'),
              Text(s.description!.trim(), style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: _action(),
      ),
    );
  }
}
