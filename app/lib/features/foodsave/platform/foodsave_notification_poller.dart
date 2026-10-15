import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../data/foodsave_api.dart';
import 'foodsave_navigation.dart';
import 'foodsave_platform_hooks.dart';

/// Polls GET /foodsave/notifications while the app is in the foreground and
/// shows each new one as a local notification; tapping opens the basket.
class FoodSaveNotificationPoller with WidgetsBindingObserver {
  FoodSaveNotificationPoller._();
  static final FoodSaveNotificationPoller instance = FoodSaveNotificationPoller._();

  static const Duration interval = Duration(seconds: 30);

  /// On the first poll after [start], only notifications this recent are
  /// shown as system notifications (older unread ones just feed the badge).
  static const Duration freshWindow = Duration(minutes: 10);

  /// Never show more than this many system notifications per poll.
  static const int maxShownPerPoll = 3;

  /// Builds the FoodSave API from the session (shared by the platform
  /// screens so tests can inject a fake HTTP client in one place).
  FoodSaveApi Function(SessionController session) apiFactory =
      (session) => FoodSaveApi(session.api);

  /// Clock (UTC); replaced in tests.
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now().toUtc();

  /// Unread count, for badges (listen to it).
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  SessionController? _session;
  FoodSaveApi? _api;
  Timer? _timer;
  bool _observing = false;
  bool _polling = false;
  bool _firstPoll = true;
  final Set<int> _shownIds = <int>{};

  /// Number of unread notifications (for badges). Updated on each poll.
  int get unreadCount => unread.value;

  bool get isRunning => _session != null;

  /// Starts polling for [session] (idempotent for the same session).
  void start(SessionController session) {
    if (identical(_session, session) && _timer != null) return;
    stop();
    _session = session;
    _api = apiFactory(session);
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

  /// Fetches unread notifications now; shows the new ones. Never throws.
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
      final now = clock();
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
        await _show(n);
      }
    } catch (e) {
      // Offline / server down: retry on the next tick.
      developer.log('FoodSave poll failed: $e', name: 'foodsave.poller');
    } finally {
      _polling = false;
    }
  }

  Future<void> _show(FoodSaveNotificationDto n) async {
    try {
      await FoodSavePlatformHooks.showNotification(
        title: n.titre,
        body: n.message,
        payload: foodSavePayloadFor(n),
      );
    } catch (e) {
      developer.log('show notification failed: $e', name: 'foodsave.poller');
    }
  }

  /// Local bookkeeping after the user read notifications in the app.
  void markReadLocally({int? id, bool all = false}) {
    if (all) {
      unread.value = 0;
    } else if (id != null && unread.value > 0) {
      unread.value = unread.value - 1;
    }
  }
}
