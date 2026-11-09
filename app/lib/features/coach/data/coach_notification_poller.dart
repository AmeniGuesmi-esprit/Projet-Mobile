import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/session/session_controller.dart';
import 'coach_api.dart';

/// Polls GET /coach/notifications while the app is in the foreground and
/// shows each new one as a local notification (booking confirmation,
/// reminder before a session, cancellation, presence validated...).
///
/// Same approach as the FoodSave poller; started / stopped from `main.dart`
/// together with it.
class CoachNotificationPoller with WidgetsBindingObserver {
  CoachNotificationPoller._();
  static final CoachNotificationPoller instance = CoachNotificationPoller._();

  static const Duration interval = Duration(seconds: 15);

  /// On the first poll after [start], only notifications this recent are shown
  /// as system notifications (older unread ones just feed the badge).
  static const Duration freshWindow = Duration(minutes: 10);

  /// Never show more than this many system notifications per poll.
  static const int maxShownPerPoll = 3;

  /// Unread count, for badges (listen to it).
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  SessionController? _session;
  CoachApi? _api;
  Timer? _timer;
  bool _observing = false;
  bool _polling = false;
  bool _firstPoll = true;
  final Set<int> _shownIds = <int>{};

  /// Starts polling for [session] (idempotent for the same session).
  void start(SessionController session) {
    if (identical(_session, session) && _timer != null) return;
    stop();
    _session = session;
    _api = CoachApi(session.api);
    _firstPoll = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _startTimer();
    unawaited(poll());
  }

  /// Stops polling and forgets the session state (logout).
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _session = null;
    _api = null;
    _shownIds.clear();
    unread.value = 0;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_session == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        unawaited(poll());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Fetches the unread notifications now and shows the new ones. Never throws.
  Future<void> poll() async {
    final session = _session;
    final api = _api;
    if (session == null || api == null || _polling) return;
    if (session.status != SessionStatus.authenticated) return;
    _polling = true;
    try {
      final items = await api.notifications(unreadOnly: true);
      if (!identical(_session, session)) return; // stopped meanwhile
      unread.value = items.length;
      final now = DateTime.now().toUtc();
      final fresh = items
          .where((n) => !_shownIds.contains(n.id))
          .where((n) =>
              !_firstPoll || now.difference(n.creeLe.toUtc()) <= freshWindow)
          .toList()
        ..sort((a, b) => a.creeLe.compareTo(b.creeLe));
      _shownIds.addAll(items.map((n) => n.id));
      _firstPoll = false;
      final toShow = fresh.length > maxShownPerPoll
          ? fresh.sublist(fresh.length - maxShownPerPoll)
          : fresh;
      for (final n in toShow) {
        try {
          await NotificationService.instance
              .show(title: n.titre, body: n.message);
        } catch (e) {
          developer.log('show notification failed: $e', name: 'coach.poller');
        }
      }
    } catch (e) {
      // Offline / server down: retry on the next tick.
      developer.log('Coach poll failed: $e', name: 'coach.poller');
    } finally {
      _polling = false;
    }
  }

  /// Local bookkeeping after the user read the notifications in the app.
  void markAllReadLocally() => unread.value = 0;
}
