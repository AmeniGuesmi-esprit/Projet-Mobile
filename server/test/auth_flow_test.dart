import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class FakeEmailSender implements EmailSender {
  final Map<String, String> lastCodeByEmail = {};

  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
    lastCodeByEmail[to] = code;
  }
}

class TestServer {
  TestServer(this.handler, this.emails, this._db);

  final Handler handler;
  final FakeEmailSender emails;
  final AppDatabase _db;

  Future<void> close() => _db.close();

  static Future<TestServer> create() async {
    final db = await AppDatabase.inMemory();
    final emails = FakeEmailSender();
    final handler = buildApp(
      db,
      const ServerConfig(
        smtpHost: '',
        smtpPort: 0,
        smtpUser: '',
        smtpPass: '',
        emailConsoleMode: true,
        dbPath: ':memory:',
        port: 0,
      ),
      emailSender: emails,
      logRequestsMiddleware: false,
    );
    return TestServer(handler, emails, db);
  }

  Future<(int, Map<String, dynamic>)> call(
    String verb,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    );
    final response = await handler(request);
    final raw = await response.readAsString();
    return (
      response.statusCode,
      raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}

Map<String, dynamic> registerBody({
  String email = 'fawzi@test.fr',
  String role = 'client',
  String? rib,
}) =>
    {
      'nom': 'Saidi',
      'prenom': 'Fawzi',
      'email': email,
      'telephone': '0612345678',
      'mot_de_passe': 'Proxilife2026!',
      'role': role,
      if (rib != null) 'rib': rib,
    };

void main() {
  late TestServer ts;

  setUp(() async {
    ts = await TestServer.create();
  });

  tearDown(() async {
    await ts.close();
  });

  test('GET /health is public', () async {
    final (status, body) = await ts.call('GET', '/health');
    expect(status, 200);
    expect(body['status'], 'ok');
    expect(body['email_mode'], 'console');
  });

  test('register sends a verification code and creates the account',
      () async {
    final (status, body) =
        await ts.call('POST', '/auth/register', body: registerBody());
    expect(status, 201);
    expect(body['id'], isA<int>());
    expect(ts.emails.lastCodeByEmail['fawzi@test.fr'], matches(r'^\d{6}$'));
  });

  test('register rejects duplicate e-mail (409), weak password and missing RIB',
      () async {
    var result = await ts.call('POST', '/auth/register', body: registerBody());
    expect(result.$1, 201);

    result = await ts.call('POST', '/auth/register', body: registerBody());
    expect(result.$1, 409);

    result = await ts.call('POST', '/auth/register',
        body: registerBody(email: 'p2@test.fr')
          ..['mot_de_passe'] = 'weak');
    expect(result.$1, 400);
    expect(result.$2['error'], contains('mot de passe'));

    result = await ts.call('POST', '/auth/register',
        body: registerBody(email: 'driver@test.fr', role: 'conducteur'));
    expect(result.$1, 400);
    expect(result.$2['error'], contains('RIB'));

    result = await ts.call('POST', '/auth/register',
        body: registerBody(
            email: 'driver@test.fr', role: 'conducteur', rib: '123'));
    expect(result.$1, 400);

    result = await ts.call('POST', '/auth/register',
        body: registerBody(
            email: 'driver@test.fr',
            role: 'conducteur',
            rib: '30004000011234567890173'));
    expect(result.$1, 201);
  });

  test('login is refused while the account is not verified (403)', () async {
    await ts.call('POST', '/auth/register', body: registerBody());
    final (status, body) = await ts.call('POST', '/auth/login', body: {
      'email': 'fawzi@test.fr',
      'mot_de_passe': 'Proxilife2026!',
    });
    expect(status, 403);
    expect(body['error'], contains('non vérifié'));
  });

  test('verify with wrong code fails, correct code activates the account',
      () async {
    await ts.call('POST', '/auth/register', body: registerBody());
    final code = ts.emails.lastCodeByEmail['fawzi@test.fr']!;
    final wrong = code == '000000' ? '000001' : '000000';

    final (badStatus, badBody) = await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': wrong});
    expect(badStatus, 400);
    expect(badBody['error'], contains('Code incorrect'));

    final (okStatus, _) = await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': code});
    expect(okStatus, 200);

    // Verification is idempotent for an active account.
    final result = await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': code});
    expect(result.$1, 200);
  });

  test('resend invalidates the old code', () async {
    await ts.call('POST', '/auth/register', body: registerBody());
    final firstCode = ts.emails.lastCodeByEmail['fawzi@test.fr']!;

    final (resendStatus, _) = await ts.call('POST', '/auth/resend',
        body: {'email': 'fawzi@test.fr'});
    expect(resendStatus, 200);
    final secondCode = ts.emails.lastCodeByEmail['fawzi@test.fr']!;

    final (oldStatus, _) = await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': firstCode});
    expect(oldStatus, 400);

    final (newStatus, _) = await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': secondCode});
    expect(newStatus, 200);
  });

  Future<String> registerVerifyAndLogin({
    String email = 'fawzi@test.fr',
    String role = 'client',
    String? rib,
  }) async {
    await ts.call('POST', '/auth/register',
        body: registerBody(email: email, role: role, rib: rib));
    final code = ts.emails.lastCodeByEmail[email]!;
    await ts.call('POST', '/auth/verify',
        body: {'email': email, 'code': code});
    final (status, body) = await ts.call('POST', '/auth/login',
        body: {'email': email, 'mot_de_passe': 'Proxilife2026!'});
    expect(status, 200);
    return body['token'] as String;
  }

  test('login returns a token usable on protected routes', () async {
    final token = await registerVerifyAndLogin();

    final (unauthStatus, _) = await ts.call('GET', '/users/me');
    expect(unauthStatus, 401);

    final (status, body) = await ts.call('GET', '/users/me', token: token);
    expect(status, 200);
    expect(body['email'], 'fawzi@test.fr');
    expect(body['role'], 'client');
    expect(body['statut_compte'], 'actif');
    expect(body['solde_centimes'], 0);
    expect(body.containsKey('mot_de_passe_hash'), isFalse);
  });

  test('wrong password is refused with 401', () async {
    await ts.call('POST', '/auth/register', body: registerBody());
    final code = ts.emails.lastCodeByEmail['fawzi@test.fr']!;
    await ts.call('POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': code});
    final (status, _) = await ts.call('POST', '/auth/login',
        body: {'email': 'fawzi@test.fr', 'mot_de_passe': 'Wrong2026!'});
    expect(status, 401);
  });

  test('PATCH /users/me updates the profile and validates input', () async {
    final token = await registerVerifyAndLogin();

    final (status, body) = await ts.call('PATCH', '/users/me',
        token: token,
        body: {'nom': 'Saidi-Martin', 'telephone': '0698765432'});
    expect(status, 200);
    expect(body['nom'], 'Saidi-Martin');
    expect(body['telephone'], '0698765432');

    final (badStatus, _) = await ts.call('PATCH', '/users/me',
        token: token, body: {'telephone': '123'});
    expect(badStatus, 400);

    final (ribStatus, _,) = await ts.call('PATCH', '/users/me',
        token: token, body: {'rib': '30004000011234567890173'});
    expect(ribStatus, 200);
  });

  test('logout invalidates the token', () async {
    final token = await registerVerifyAndLogin();

    final (logoutStatus, _) =
        await ts.call('POST', '/auth/logout', token: token);
    expect(logoutStatus, 204);

    final (status, _) = await ts.call('GET', '/users/me', token: token);
    expect(status, 401);
  });

  test('DELETE /users/me removes the account (no password required)',
      () async {
    final token = await registerVerifyAndLogin();

    final (status, _) = await ts.call('DELETE', '/users/me', token: token);
    expect(status, 200);

    final (afterStatus, _) = await ts.call('GET', '/users/me', token: token);
    expect(afterStatus, 401);
  });
}
