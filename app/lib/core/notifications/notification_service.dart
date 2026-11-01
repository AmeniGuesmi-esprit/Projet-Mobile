import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications (verification, payments, refunds, FoodSave). The
/// POST_NOTIFICATIONS permission is never requested at startup: only from the
/// Profile settings or an explicit in-context prompt.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'proxilife_general';
  static const _channelName = 'ProxiLife';
  static const _channelDesc = 'Notifications ProxiLife (compte et paiements)';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called with the payload when the user taps a notification while the
  /// app is running. When null, the payload is kept for [takeLaunchPayload].
  void Function(String payload)? onTap;

  String? _pendingPayload;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _pendingPayload = payload;
      }
    } catch (e) {
      developer.log('Launch details unavailable: $e',
          name: 'notifications');
    }
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final callback = onTap;
    if (callback != null) {
      callback(payload);
    } else {
      _pendingPayload = payload;
    }
  }

  /// Payload of the notification that launched the app (or was tapped
  /// before [onTap] was set). Returned once, then cleared.
  String? takeLaunchPayload() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    return payload;
  }

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns true if granted.
  Future<bool> ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Shows a notification. [payload] is handed back to [onTap] on tap.
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
