import 'dart:convert';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeEmailSender implements EmailSender {
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

class _FailingEmailSender implements EmailSender {
  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
    throw StateError('SMTP indisponible (simulé)');
  }
}

Future<(int, Map<String, dynamic>)> call(
  Handler handler,
  String verb,
  String path, {
  Map<String, dynamic>? body,
}) async {
  final request = Request(
    verb,
    Uri.parse('http://test$path'),
    body: body == null ? null : jsonEncode(body),
    headers: {if (body != null) 'content-type': 'application/json'},
  );
  final response = await handler(request);
  final raw = await response.readAsString();
  return (
    response.statusCode,
    raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>,
  );
}

void main() {
  test('registration survives an SMTP failure; fallback still carries the code',
      () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final fallback = _FakeEmailSender();
    final handler = buildApp(
      db,
      const ServerConfig(
        smtpHost: 'smtp.gmail.com',
        smtpPort: 465,
        smtpUser: 'user@gmail.com',
        smtpPass: 'app-password',
        emailConsoleMode: false,
        dbPath: ':memory:',
        port: 0,
      ),
      emailSender: ResilientEmailSender(
        primary: _FailingEmailSender(),
        fallback: fallback,
      ),
      logRequestsMiddleware: false,
    );

    final (status, _) = await call(handler, 'POST', '/auth/register', body: {
      'nom': 'Saidi',
      'prenom': 'Fawzi',
      'email': 'fawzi@test.fr',
      'telephone': '0612345678',
      'mot_de_passe': 'Proxilife2026!',
      'role': 'client',
    });
    expect(status, 201);

    // The console-style fallback delivered the code even though SMTP threw.
    final code = fallback.lastCodeByEmail['fawzi@test.fr'];
    expect(code, matches(r'^\d{6}$'));

    // The account is fully usable afterwards.
    final (verifyStatus, _) = await call(handler, 'POST', '/auth/verify',
        body: {'email': 'fawzi@test.fr', 'code': code});
    expect(verifyStatus, 200);
  });
}
