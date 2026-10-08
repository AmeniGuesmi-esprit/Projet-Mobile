// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../api/api_client.dart';
import 'stores.dart';

enum SessionStatus { unknown, unauthenticated, authenticated }

/// Central app session: token, current user, biometric preferences.
class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient api,
    required TokenStore tokenStore,
    required this.settings,
  })  : _api = api,
        _tokenStore = tokenStore;

  final ApiClient _api;
  final TokenStore _tokenStore;
  final SettingsStore settings;

  SessionStatus status = SessionStatus.unknown;
  UserDto? user;
  bool biometricsEnabled = false;
  String? lastEmail;

  ApiClient get api => _api;

  /// Cold start: restore the stored token, then validate it with /users/me.
  Future<void> restore() async {
    biometricsEnabled = await settings.getBiometricsEnabled();
    lastEmail = await settings.getLastEmail();
    final token = await _tokenStore.read();
    if (token == null) {
      status = SessionStatus.unauthenticated;
      notifyListeners();
      return;
    }
    _api.token = token;
    try {
      await refreshUser();
      status = SessionStatus.authenticated;
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _tokenStore.clear(); // expired session
      }
      _api.token = null;
      status = SessionStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> login(String email, String motDePasse) async {
    final data = await _api.postJson('/auth/login', {
      'email': email,
      'mot_de_passe': motDePasse,
    });
    final response = AuthResponseDto.fromJson(data);
    _api.token = response.token;
    await _tokenStore.write(response.token);
    await settings.setLastEmail(email.trim());
    lastEmail = email.trim();
    user = response.utilisateur;
    status = SessionStatus.authenticated;
    notifyListeners();
  }

  /// Registration: the account is created unverified; the app then shows the
  /// verification screen for [email].
  Future<void> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String motDePasse,
    required UserRole role,
    String? rib,
  }) async {
    await _api.postJson('/auth/register', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': telephone,
      'mot_de_passe': motDePasse,
      'role': role.apiValue,
      if (rib != null && rib.isNotEmpty) 'rib': rib,
    });
  }

  Future<void> verify(String email, String code) =>
      _api.postJson('/auth/verify', {'email': email, 'code': code});

  Future<void> resendCode(String email) =>
      _api.postJson('/auth/resend', {'email': email});

  Future<void> logout() async {
    try {
      await _api.postJson('/auth/logout');
    } on ApiException {
      // Local logout stays valid even if the server is unreachable.
    }
    await _tokenStore.clear();
    _api.token = null;
    user = null;
    status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final data = await _api.getJson('/users/me');
    user = UserDto.fromJson(data);
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final data = await _api.patchJson('/users/me', fields);
    user = UserDto.fromJson(data);
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await _api.deleteJson('/users/me');
    await _tokenStore.clear();
    _api.token = null;
    user = null;
    status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> setBiometricsEnabled(bool value) async {
    biometricsEnabled = value;
    await settings.setBiometricsEnabled(value);
    notifyListeners();
  }
}
