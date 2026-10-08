import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../config/server_config.dart';

/// Sends e-mails. Two modes: console (dev/offline default) and SMTP (Gmail).
abstract class EmailSender {
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  });
}

/// Dev mode: prints the e-mail in the server log instead of sending it.
class ConsoleEmailSender implements EmailSender {
  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
    stdout.writeln('┌─ E-mail simulé ─────────────────────────────');
    stdout.writeln('│ À        : $to');
    stdout.writeln('│ Objet    : Votre code de vérification ProxiLife');
    stdout.writeln('│ Message  : Bonjour $prenom, votre code est : $code');
    stdout.writeln('└─────────────────────────────────────────────');
  }
}

/// Production mode: real delivery via Gmail SMTP (Google App Password).
class SmtpEmailSender implements EmailSender {
  SmtpEmailSender(this._config);

  final ServerConfig _config;

  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
    final smtpServer = SmtpServer(
      _config.smtpHost,
      port: _config.smtpPort,
      ssl: _config.smtpPort == 465,
      username: _config.smtpUser,
      password: _config.smtpPass,
    );
    final message = Message()
      ..from = Address(_config.smtpUser, 'ProxiLife')
      ..recipients.add(to)
      ..subject = 'Votre code de vérification ProxiLife'
      ..text = 'Bonjour $prenom,\n\n'
          'Voici votre code de vérification ProxiLife : $code\n'
          'Il est valable 10 minutes.\n\n'
          "Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail."
      ..html = '<p>Bonjour $prenom,</p>'
          '<p>Voici votre code de vérification ProxiLife : '
          '<strong style="font-size:24px;letter-spacing:4px">$code</strong></p>'
          '<p>Il est valable 10 minutes.</p>'
          '<p>Si vous n\'êtes pas à l\'origine de cette demande, '
          'ignorez cet e-mail.</p>';
    await send(message, smtpServer);
  }
}

EmailSender createEmailSender(ServerConfig config) {
  if (!config.emailConsoleMode &&
      config.smtpUser.isNotEmpty &&
      config.smtpPass.isNotEmpty) {
    return SmtpEmailSender(config);
  }
  return ConsoleEmailSender();
}
