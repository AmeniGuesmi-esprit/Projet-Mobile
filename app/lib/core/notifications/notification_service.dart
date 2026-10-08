import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications (verification, payments, refunds). The POST_NOTIFICATIONS
/// permission is requested explicitly from the Profile settings only.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'proxilife_general';
  static const _channelName = 'ProxiLife';
  static const _channelDesc = 'Notifications ProxiLife (compte et paiements)';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        settings: const InitializationSettings(android: android));
  }

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns true if granted.
  Future<bool> ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<void> show({required String title, required String body}) async {
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
    );
  }
}
