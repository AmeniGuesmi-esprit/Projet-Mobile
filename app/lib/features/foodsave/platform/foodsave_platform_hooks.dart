import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';

/// Shows a local notification (same shape as [NotificationService.show]).
typedef NotificationShower = Future<void> Function({
  required String title,
  required String body,
  String? payload,
});

/// Plugin-backed side effects used by the FoodSave platform layer, gathered
/// in one place so widget tests can swap them for fakes (no platform
/// channels in tests).
class FoodSavePlatformHooks {
  const FoodSavePlatformHooks._();

  static NotificationShower showNotification =
      NotificationService.instance.show;

  static Future<bool> Function() requestNotificationPermission =
      NotificationService.instance.ensurePermission;

  /// Persistent boolean flags (one-time prompts). Errors read as false.
  static Future<bool> Function(String key) readFlag = _readPref;
  static Future<void> Function(String key, bool value) writeFlag = _writePref;

  static Future<bool> _readPref(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (e) {
      developer.log('readFlag($key) failed: $e', name: 'foodsave.platform');
      return false;
    }
  }

  static Future<void> _writePref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      developer.log('writeFlag($key) failed: $e', name: 'foodsave.platform');
    }
  }
}
