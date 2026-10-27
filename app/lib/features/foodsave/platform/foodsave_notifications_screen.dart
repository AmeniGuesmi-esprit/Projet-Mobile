import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'foodsave_navigation.dart';
import 'foodsave_notification_poller.dart';

/// FoodSave in-app notifications: newest first, unread emphasised, tap to
/// open the basket / reservation.
class FoodSaveNotificationsScreen extends StatefulWidget {
  const FoodSaveNotificationsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<FoodSaveNotificationsScreen> createState() =>
      _FoodSaveNotificationsScreenState();
}

class _FoodSaveNotificationsScreenState
    extends State<FoodSaveNotificationsScreen> {
  late final FoodSaveApi _api =
      FoodSaveNotificationPoller.instance.apiFactory(widget.session);
  late Future<List<FoodSaveNotificationDto>> _future = _load();

  /// Ids read in this screen (optimistic, before the next reload).
  final Set<int> _readIds = <int>{};

  Future<List<FoodSaveNotificationDto>> _load() async {
    final items = await _api.notifications();
    _readIds.clear();
    FoodSaveNotificationPoller.instance.unread.value =
        items.where((n) => !n.lu).length;
    return items;
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Rendered by the FutureBuilder.
    }
  }

  bool _isUnread(FoodSaveNotificationDto n) => !n.lu && !_readIds.contains(n.id);

  Future<void> _open(FoodSaveNotificationDto n) async {
    if (_isUnread(n)) {
      setState(() => _readIds.add(n.id));
      FoodSaveNotificationPoller.instance.markReadLocally(id: n.id);
      try {
        await _api.markNotificationRead(n.id);
      } catch (_) {
        // Best effort: the next refresh shows the real state.
      }
    }
    if (!mounted) return;
    final screen =
        foodSaveScreenForPayload(foodSavePayloadFor(n), widget.session);
    if (screen == null || screen is FoodSaveNotificationsScreen) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _markAll(List<FoodSaveNotificationDto> items) async {
    final previous = Set<int>.of(_readIds);
    setState(() => _readIds.addAll(items.map((n) => n.id)));
    try {
      await _api.markAllNotificationsRead();
      FoodSaveNotificationPoller.instance.markReadLocally(all: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Toutes les notifications sont marquées comme lues')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _readIds
        ..clear()
        ..addAll(previous));
      showFoodSaveError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FoodSaveNotificationDto>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data;
        final hasUnread = items != null && items.any(_isUnread);
        final Widget body;
        if (snapshot.connectionState == ConnectionState.waiting &&
            items == null) {
          body = const _NotificationListSkeleton(key: ValueKey('loading'));
        } else if (snapshot.hasError) {
          body = FoodSaveErrorView(
              key: const ValueKey('error'),
              error: snapshot.error,
              onRetry: _reload);
        } else if (items == null || items.isEmpty) {
          body = RefreshIndicator(
            key: const ValueKey('empty'),
            onRefresh: _reload,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Aucune notification',
                    message:
                        'Vous serez averti ici des nouveaux paniers et de vos réservations.',
                    color: AppColors.moduleFoodSaveDeep,
                  ),
                ),
              ),
            ),
          );
        } else {
          final now = DateTime.now();
          body = RefreshIndicator(
            key: const ValueKey('list'),
            onRefresh: _reload,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs,
                  AppSpacing.md, AppSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) {
                final n = items[i];
                return FadeSlideIn(
                  key: ValueKey('notif-${n.id}'),
                  index: i,
                  child: _NotificationTile(
                    notification: n,
                    unread: _isUnread(n),
                    timeLabel: formatRelativeFr(n.creeLe, now),
                    onTap: () => _open(n),
                  ),
                );
              },
            ),
          );
        }

        final disableAnimations =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              IconButton(
                tooltip: 'Tout marquer comme lu',
                icon: const Icon(Icons.done_all_rounded),
                onPressed: hasUnread ? () => _markAll(items) : null,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
          ),
          body: AnimatedSwitcher(
            duration:
                disableAnimations ? Duration.zero : FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            switchOutCurve: FoodSaveMotion.curve,
            child: body,
          ),
        );
      },
    );
  }
}

/// "À l'instant", "Il y a 5 min", "Il y a 2 h", "Hier à 18:30",
/// "Il y a 3 j", then "12/10/2026". [time] may be UTC; shown in local time.
String formatRelativeFr(DateTime time, DateTime now) {
  final local = time.toLocal();
  final nowLocal = now.toLocal();
  final diff = nowLocal.difference(local);
  if (diff.inSeconds < 60) return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Il y a ${diff.inHours} h';
  if (days == 1) return 'Hier à ${DateFormat('HH:mm').format(local)}';
  if (days < 7) return 'Il y a $days j';
  return DateFormat('dd/MM/yyyy').format(local);
}

/// Icon + palette colour per notification type. [darkIcon] = contrast rule
/// for warning / FoodSave fills (dark foreground on the tint).
class _TypeStyle {
  const _TypeStyle(this.icon, this.color, {this.darkIcon = false});

  final IconData icon;
  final Color color;
  final bool darkIcon;

  static _TypeStyle of(FoodSaveNotificationType type) => switch (type) {
        FoodSaveNotificationType.nouveauPanier => const _TypeStyle(
            Icons.shopping_basket_outlined, AppColors.moduleFoodSave),
        FoodSaveNotificationType.qrExpireBientot => const _TypeStyle(
            Icons.timer_outlined, AppColors.warning,
            darkIcon: true),
        FoodSaveNotificationType.reservationExpiree => const _TypeStyle(
            Icons.timer_off_outlined, AppColors.warning,
            darkIcon: true),
        FoodSaveNotificationType.panierAnnule =>
          const _TypeStyle(Icons.block_rounded, AppColors.error),
        FoodSaveNotificationType.retraitEffectue => const _TypeStyle(
            Icons.check_circle_outline_rounded, AppColors.success),
        FoodSaveNotificationType.reservationConfirmee =>
          const _TypeStyle(Icons.qr_code_2_rounded, AppColors.info),
        FoodSaveNotificationType.nouvelleReservation => const _TypeStyle(
            Icons.shopping_bag_outlined, AppColors.moduleFoodSave),
        FoodSaveNotificationType.reservationAnnulee =>
          const _TypeStyle(Icons.event_busy_outlined, AppColors.error),
      };
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.unread,
    required this.timeLabel,
    required this.onTap,
  });

  final FoodSaveNotificationDto notification;
  final bool unread;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _TypeStyle.of(notification.type);
    return Semantics(
      button: true,
      label: '${unread ? 'Non lue. ' : ''}${notification.titre}. '
          '${notification.message}. $timeLabel',
      excludeSemantics: true,
      child: Material(
        color: unread ? AppColors.moduleFoodSaveSoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: unread
                ? AppColors.moduleFoodSave.withValues(alpha: 0.35)
                : AppColors.outlineSoft,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: style.color
                          .withValues(alpha: style.darkIcon ? 0.22 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(style.icon,
                        size: 22,
                        color: style.darkIcon ? AppColors.text : style.color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                notification.titre,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (unread) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.moduleFoodSaveDeep,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          notification.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondaryStrong),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          timeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryStrong,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationListSkeleton extends StatelessWidget {
  const _NotificationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, _) => const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 44, width: 44, radius: AppRadius.pill),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 16, width: 180),
                  SizedBox(height: AppSpacing.xs),
                  SkeletonBox(height: 14),
                  SizedBox(height: AppSpacing.xxs),
                  SkeletonBox(height: 12, width: 90),
                ],
              ),
            ),
          ],
        ),
      );
}

/// AppBar bell with the unread badge; opens [FoodSaveNotificationsScreen].
/// Other FoodSave screens can drop it in their `actions`.
class FoodSaveNotificationsButton extends StatelessWidget {
  const FoodSaveNotificationsButton({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FoodSaveNotificationPoller.instance.unread,
      builder: (context, count, _) => IconButton(
        tooltip: count == 0
            ? 'Notifications'
            : 'Notifications, $count non lue${count > 1 ? 's' : ''}',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => FoodSaveNotificationsScreen(session: session))),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          backgroundColor: AppColors.moduleFoodSaveDeep,
          textColor: AppColors.surface,
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}
