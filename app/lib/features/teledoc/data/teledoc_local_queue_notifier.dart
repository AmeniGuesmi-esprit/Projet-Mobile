import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/session/stores.dart';
import '../domain/teledoc_queue_tracker.dart';

/// Shows queue events as Android local notifications through the app's
/// existing [NotificationService], only if the user enabled notifications
/// (same preference as the Profile screen toggle).
///
/// Limit (no Firebase in this project, AGENTS.md): events are detected by the
/// app's own polling, so they arrive while the app process is alive (screen
/// open or app recently backgrounded), not when Android has killed it.
class TeledocLocalQueueNotifier implements TeledocQueueNotifier {
  TeledocLocalQueueNotifier(this._settings);

  final SettingsStore _settings;

  @override
  Future<void> notify(
    TeledocQueueEvent event,
    TeledocQueueStatusDto status,
  ) async {
    if (!await _settings.getNotificationsEnabled()) return;
    final text = teledocNotificationText(event, status);
    await NotificationService.instance.show(title: text.title, body: text.body);
  }
}

/// Asks for the Android 13+ permission and stores the shared preference.
/// Returns true when notifications are now enabled.
Future<bool> enableTeledocNotifications(SettingsStore settings) async {
  final granted = await NotificationService.instance.ensurePermission();
  if (granted) await settings.setNotificationsEnabled(true);
  return granted;
}
