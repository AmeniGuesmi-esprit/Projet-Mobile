import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/user_repository.dart';
import 'passwords.dart';

/// Issues and resolves session tokens. Raw tokens are random 32-byte values
/// (base64url); only their SHA-256 hash is stored, with a 30-day expiration.
class SessionService {
  SessionService(this._db, this._users);

  static const Duration sessionLifetime = Duration(days: 30);

  final Database _db;
  final UserRepository _users;

  Future<String> createSession(int utilisateurId) async {
    final raw = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final token = base64Url.encode(raw);
    await _db.insert('session', {
      'token_hash': sha256HexOf(token),
      'date_expiration':
          DateTime.now().add(sessionLifetime).toIso8601String(),
      'utilisateur_id': utilisateurId,
      'cree_le': DateTime.now().toIso8601String(),
    });
    return token;
  }

  /// Returns the session's user row if the token exists and is not expired.
  Future<Map<String, Object?>?> resolveUser(String token) async {
    final rows = await _db.query(
      'session',
      where: 'token_hash = ?',
      whereArgs: [sha256HexOf(token)],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final expiration = DateTime.parse(row['date_expiration'] as String);
    if (DateTime.now().isAfter(expiration)) {
      await revoke(token);
      return null;
    }
    return _users.findById(row['utilisateur_id'] as int);
  }

  Future<void> revoke(String token) => _db.delete(
        'session',
        where: 'token_hash = ?',
        whereArgs: [sha256HexOf(token)],
      );
}
