import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/core/session/stores.dart';

class FakeTokenStore implements TokenStore {
  FakeTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

class FakeSettingsStore implements SettingsStore {
  bool biometrics = false;
  String? email;
  bool notifications = false;

  @override
  Future<bool> getBiometricsEnabled() async => biometrics;
  @override
  Future<void> setBiometricsEnabled(bool value) async => biometrics = value;
  @override
  Future<String?> getLastEmail() async => email;
  @override
  Future<void> setLastEmail(String value) async => email = value;
  @override
  Future<bool> getNotificationsEnabled() async => notifications;
  @override
  Future<void> setNotificationsEnabled(bool value) async =>
      notifications = value;
}

SessionController makeTestSession({ApiClient? api, String? storedToken}) {
  return SessionController(
    api: api ?? ApiClient(baseUrl: 'http://127.0.0.1:1'),
    tokenStore: FakeTokenStore(storedToken),
    settings: FakeSettingsStore(),
  );
}
