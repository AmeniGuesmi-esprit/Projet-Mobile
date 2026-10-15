import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../config/server_config.dart';
import 'qr_png.dart';
import 'reservation_qr_email.dart';

/// Sends e-mails. Two modes: console (dev/offline default) and SMTP (Gmail).
abstract class EmailSender {
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  });
}

/// Sends the FoodSave pickup QR code once a reservation is paid. Kept apart
/// from [EmailSender] so existing fakes don't have to implement it.
abstract class ReservationMailer {
  Future<void> sendReservationQr(ReservationQrEmail email);
}

/// Dev mode: prints the e-mail in the server log instead of sending it.
class ConsoleEmailSender implements EmailSender, ReservationMailer {
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

  @override
  Future<void> sendReservationQr(ReservationQrEmail email) async {
    stdout.writeln('┌─ E-mail simulé ─────────────────────────────');
    stdout.writeln('│ À        : ${email.to}');
    stdout.writeln('│ Objet    : ${email.subject}');
    stdout.writeln('│ Retrait  : ${email.pickupWindow}');
    stdout.writeln('│ QR       : ${email.qrToken}');
    stdout.writeln('└─────────────────────────────────────────────');
  }
}

/// Production mode: real delivery via Gmail SMTP (Google App Password).
class SmtpEmailSender implements EmailSender, ReservationMailer {
  SmtpEmailSender(this._config);

  final ServerConfig _config;

  SmtpServer get _server => SmtpServer(
        _config.smtpHost,
        port: _config.smtpPort,
        ssl: _config.smtpPort == 465,
        username: _config.smtpUser,
        password: _config.smtpPass,
      );

  @override
  Future<void> sendVerificationCode({
    required String to,
    required String prenom,
    required String code,
  }) async {
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
    await send(message, _server);
  }

  @override
  Future<void> sendReservationQr(ReservationQrEmail email) async {
    final png = encodeQrPng(email.qrToken);
    final message = Message()
      ..from = Address(_config.smtpUser, 'ProxiLife FoodSave')
      ..recipients.add(email.to)
      ..subject = email.subject
      ..text = email.text
      ..html = email.html
      ..attachments = [
        StreamAttachment(Stream.value(png), 'image/png',
            fileName: 'qr-${email.reference}.png')
          ..location = Location.inline
          ..cid = reservationQrCid,
      ];
    await send(message, _server);
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
