import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage of the session token. Android Keystore-backed encryption.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'proxilife.sessionToken';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// App-level boolean/string settings (biometric toggle, last e-mail used).
abstract class SettingsStore {
  Future<bool> getBiometricsEnabled();
  Future<void> setBiometricsEnabled(bool value);
  Future<String?> getLastEmail();
  Future<void> setLastEmail(String email);
  Future<bool> getNotificationsEnabled();
  Future<void> setNotificationsEnabled(bool value);
}

class SharedPrefsSettingsStore implements SettingsStore {
  static const _biometricsKey = 'proxilife.biometricsEnabled';
  static const _lastEmailKey = 'proxilife.lastEmail';
  static const _notificationsKey = 'proxilife.notificationsEnabled';

  @override
  Future<bool> getBiometricsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_biometricsKey) ?? false;
  @override
  Future<void> setBiometricsEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_biometricsKey, value);
  @override
  Future<String?> getLastEmail() async =>
      (await SharedPreferences.getInstance()).getString(_lastEmailKey);
  @override
  Future<void> setLastEmail(String email) async =>
      (await SharedPreferences.getInstance()).setString(_lastEmailKey, email);
  @override
  Future<bool> getNotificationsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_notificationsKey) ??
      false;
  @override
  Future<void> setNotificationsEnabled(bool value) async =>
      (await SharedPreferences.getInstance())
          .setBool(_notificationsKey, value);
}
