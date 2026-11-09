import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/session/session_controller.dart';
import '../foodsave/platform/foodsave_navigation.dart' show appNavigatorKey;
import 'demande_detail_screen.dart';
import 'service_now_api.dart';

const String _payloadPrefix = 'servicenow:';

/// Opens the request of a tapped notification. Returns false when the
/// payload belongs to another module.
bool openServiceNowPayload(String payload, SessionController session) {
  if (!payload.startsWith(_payloadPrefix)) return false;
  final id = int.tryParse(payload.substring(_payloadPrefix.length));
  if (id != null) unawaited(_openDemande(id, session));
  return true;
}

Future<void> _openDemande(int id, SessionController session) async {
  if (session.status != SessionStatus.authenticated) return;
  try {
    final demande = await ServiceNowApi(session.api).demande(id);
    await appNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => DemandeDetailScreen(session: session, demande: demande),
      ),
    );
  } catch (e) {
    developer.log('Demande $id non ouverte : $e', name: 'servicenow');
  }
}

/// Asks the server for new ServiceNow notifications and shows them on the
/// phone. Like FoodSave's poller, it works while the app is open: the project
/// has no push service (Firebase), so nothing arrives once the app is closed.
/// A notification that could not be shown yet waits on the server.
class ServiceNowNotificationPoller with WidgetsBindingObserver {
  ServiceNowNotificationPoller._();
  static final ServiceNowNotificationPoller instance =
      ServiceNowNotificationPoller._();

  static const Duration _interval = Duration(seconds: 10);

  SessionController? _session;
  Timer? _timer;
  bool _observing = false;
  bool _polling = false;

  /// Starts polling for [session] (does nothing if already running for it).
  void start(SessionController session) {
    if (identical(_session, session) && _timer != null) return;
    stop();
    _session = session;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _startTimer();
    unawaited(_poll());
  }

  /// Stops polling (logout).
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _session = null;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(_poll()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_session == null) return;
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      unawaited(_poll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null ||
        _polling ||
        session.status != SessionStatus.authenticated) {
      return;
    }
    _polling = true;
    try {
      // Left on the server until the user turns notifications on.
      if (!await session.settings.getNotificationsEnabled()) return;
      final items = await ServiceNowApi(session.api).takeNotifications();
      for (final item in items) {
        await NotificationService.instance.show(
          title: item.titre,
          body: item.message,
          payload: '$_payloadPrefix${item.demandeId}',
        );
      }
    } catch (e) {
      // Offline or server down: the next tick tries again.
      developer.log('Notifications indisponibles : $e', name: 'servicenow');
    } finally {
      _polling = false;
    }
  }
}
