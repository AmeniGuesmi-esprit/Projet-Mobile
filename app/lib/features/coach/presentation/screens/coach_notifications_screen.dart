import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/coach_api.dart';
import '../../data/coach_notification_poller.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';
import 'coach_booking_detail_screen.dart';
import 'coach_session_manage_screen.dart';

/// App-bar bell with the unread badge; opens [CoachNotificationsScreen].
class CoachBellButton extends StatelessWidget {
  const CoachBellButton({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CoachNotificationPoller.instance.unread,
      builder: (context, count, _) => IconButton(
        tooltip: count > 0
            ? 'Notifications ($count non lues)'
            : 'Notifications',
        onPressed: () => pushCoach<void>(
          context,
          CoachNotificationsScreen(session: session),
        ),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}

/// « Notifications » of the module: booking confirmation, reminder before a
/// session, cancellation, presence validated... Unread ones are highlighted;
/// they are all marked as read once the list is displayed.
class CoachNotificationsScreen extends StatefulWidget {
  const CoachNotificationsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CoachNotificationsScreen> createState() =>
      _CoachNotificationsScreenState();
}

class _CoachNotificationsScreenState extends State<CoachNotificationsScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  late Future<List<CoachNotificationDto>> _future = _load();

  Future<List<CoachNotificationDto>> _load() async {
    final items = await _api.notifications();
    if (items.any((n) => !n.lu)) {
      // Fire and forget: the highlight below uses the flags read just now.
      unawaited(_api.markAllRead().then((_) {
        CoachNotificationPoller.instance.markAllReadLocally();
      }).catchError((Object _) {}));
    }
    return items;
  }

  void _reload() => setState(() {
        _future = _load();
      });

  IconData _icon(CoachNotificationType type) => switch (type) {
        CoachNotificationType.reservationConfirmee =>
          Icons.check_circle_outline,
        CoachNotificationType.rappelSeance => Icons.alarm,
        CoachNotificationType.seanceAnnulee => Icons.event_busy_outlined,
        CoachNotificationType.seanceModifiee => Icons.edit_calendar_outlined,
        CoachNotificationType.presenceValidee => Icons.how_to_reg_outlined,
        CoachNotificationType.nouvelleReservation =>
          Icons.person_add_alt_outlined,
        CoachNotificationType.reservationAnnulee =>
          Icons.person_remove_alt_1_outlined,
      };

  void _open(CoachNotificationDto n) {
    final isCoach = widget.session.user?.role == UserRole.coach;
    if (isCoach && n.seanceId != null) {
      pushCoach<void>(
        context,
        CoachSessionManageScreen(
            session: widget.session, sessionId: n.seanceId!),
      );
    } else if (!isCoach && n.reservationId != null) {
      pushCoach<void>(
        context,
        CoachBookingDetailScreen(
            session: widget.session, bookingId: n.reservationId!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: CoachAsyncView<List<CoachNotificationDto>>(
        future: _future,
        onRetry: _reload,
        builder: (context, items) {
          return RefreshIndicator(
            color: CoachColors.brandDeep,
            onRefresh: () async {
              _reload();
              await _future.catchError((_) => <CoachNotificationDto>[]);
            },
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: AppSpacing.xl),
                      EmptyState(
                        icon: Icons.notifications_none,
                        title: 'Aucune notification',
                        message: 'Confirmations, rappels et annulations '
                            'apparaîtront ici.',
                        color: AppColors.moduleCoachProche,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        color: n.lu ? null : CoachColors.brandSoft,
                        child: InkWell(
                          onTap: () => _open(n),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(_icon(n.type),
                                    color: CoachColors.brandDeep),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(n.titre,
                                          style: theme.textTheme.titleMedium),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(n.message,
                                          style: theme.textTheme.bodyMedium),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(coachWhen(n.creeLe),
                                          style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                                if (!n.lu)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8, top: 4),
                                    child: Icon(Icons.circle,
                                        size: 10, color: CoachColors.brandDeep),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
