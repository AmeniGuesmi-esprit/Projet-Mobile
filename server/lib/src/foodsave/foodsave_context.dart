import 'dart:convert';
import 'dart:developer' as developer;

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../email/email_sender.dart';
import '../repositories/user_repository.dart';
import '../services/payment_service.dart';
import 'services/reverse_geocoder.dart';

/// Dependencies shared by every FoodSave service. Built once in `buildApp`.
class FoodSaveContext {
  FoodSaveContext({
    required this.db,
    required this.users,
    required this.payments,
    required this.uploadsDir,
    this.qrTtl = const Duration(minutes: 30),
    this.mailer,
    this.geocoder,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    journal = FoodSaveJournal(db, now);
    notifier = FoodSaveNotifier(db, now);
  }

  final Database db;
  final UserRepository users;

  /// Existing payment module — reused as-is for basket payments/refunds.
  final PaymentService payments;

  /// Directory where basket photos are stored (created on demand).
  final String uploadsDir;

  /// QR lifetime once the pickup window is open (see FoodSaveRules.qrExpiry).
  final Duration qrTtl;

  /// E-mails the pickup QR code to the client once paid (null: no e-mail).
  final ReservationMailer? mailer;

  /// GPS → address for the store form (null: feature unavailable).
  final ReverseGeocoder? geocoder;

  final DateTime Function() _clock;

  late final FoodSaveJournal journal;
  late final FoodSaveNotifier notifier;

  /// Current time in UTC, truncated to the millisecond so that ISO strings
  /// always have the same width (lexical order == chronological order).
  /// Tests inject a fake clock.
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(
      _clock().millisecondsSinceEpoch,
      isUtc: true);

  String nowIso() => now().toIso8601String();
}

/// Role guard helpers for FoodSave routes.
UserRole roleOf(Map<String, Object?> userRow) =>
    UserRole.parse(userRow['role'] as String);

void requireMerchant(Map<String, Object?> userRow) {
  if (roleOf(userRow) != UserRole.commercant) {
    throw ApiError.forbidden('Espace réservé aux commerçants');
  }
}

/// Append-only audit log (`foodsave_journal`). Never throws: logging must not
/// break the business operation.
class FoodSaveJournal {
  FoodSaveJournal(this._db, this._now);

  final DatabaseExecutor _db;
  final DateTime Function() _now;

  /// [executor] lets callers log inside their own transaction.
  Future<void> log(
    String evenement, {
    int? utilisateurId,
    int? panierId,
    int? reservationId,
    Map<String, Object?>? details,
    DatabaseExecutor? executor,
  }) async {
    try {
      await (executor ?? _db).insert('foodsave_journal', {
        'evenement': evenement,
        'utilisateur_id': utilisateurId,
        'panier_id': panierId,
        'reservation_id': reservationId,
        'details': details == null ? null : jsonEncode(details),
        'cree_le': _now().toUtc().toIso8601String(),
      });
      developer.log(
          '$evenement panier=$panierId reservation=$reservationId '
          'user=$utilisateurId',
          name: 'foodsave');
    } catch (e, st) {
      developer.log('journal failure',
          error: e, stackTrace: st, name: 'foodsave');
    }
  }
}

/// Inserts in-app notifications. Idempotent per [cleEvenement]: the same
/// event never produces two notifications (UNIQUE constraint + IGNORE).
class FoodSaveNotifier {
  FoodSaveNotifier(this._db, this._now);

  final DatabaseExecutor _db;
  final DateTime Function() _now;

  /// Returns true when a new notification was created.
  Future<bool> notifyUser({
    required int userId,
    required FoodSaveNotificationType type,
    required String titre,
    required String message,
    required String cleEvenement,
    int? panierId,
    int? reservationId,
    DatabaseExecutor? executor,
  }) async {
    final id = await (executor ?? _db).insert(
      'foodsave_notification',
      {
        'utilisateur_id': userId,
        'type': type.apiValue,
        'titre': titre,
        'message': message,
        'panier_id': panierId,
        'reservation_id': reservationId,
        'cle_evenement': cleEvenement,
        'lu': 0,
        'cree_le': _now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0;
  }
}
