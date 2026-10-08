import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/passwords.dart';

/// SQL access for the `code_verification` table. Codes are stored as
/// SHA-256 hashes bound to the account e-mail, expire after 10 minutes and
/// allow at most 5 attempts.
class VerificationRepository {
  VerificationRepository(this._db);

  static const Duration codeLifetime = Duration(minutes: 10);
  static const int maxAttempts = 5;

  final Database _db;

  String hashOf(String email, String code) =>
      sha256HexOf('${normalizeEmail(email)}:$code');

  Future<int> create({
    required int utilisateurId,
    required String email,
    required String code,
    VerificationMethod methode = VerificationMethod.email,
  }) async {
    // Invalidate previous codes for this account.
    await _db.update(
      'code_verification',
      {'statut': VerificationCodeStatus.expire.apiValue},
      where: 'utilisateur_id = ? AND statut = ?',
      whereArgs: [utilisateurId, VerificationCodeStatus.enAttente.apiValue],
    );
    return _db.insert('code_verification', {
      'code_hash': hashOf(email, code),
      'methode': methode.apiValue,
      'date_expiration':
          DateTime.now().add(codeLifetime).toIso8601String(),
      'statut': VerificationCodeStatus.enAttente.apiValue,
      'tentatives': 0,
      'utilisateur_id': utilisateurId,
      'cree_le': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, Object?>?> latestPending(int utilisateurId) async {
    final rows = await _db.query(
      'code_verification',
      where: 'utilisateur_id = ? AND statut = ?',
      whereArgs: [utilisateurId, VerificationCodeStatus.enAttente.apiValue],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> incrementAttempts(int id) async {
    await _db.rawUpdate(
      'UPDATE code_verification SET tentatives = tentatives + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> markValidated(int id) => _db.update(
        'code_verification',
        {'statut': VerificationCodeStatus.valide.apiValue},
        where: 'id = ?',
        whereArgs: [id],
      );

  bool isExpired(Map<String, Object?> row, {DateTime? now}) {
    final expiration = DateTime.parse(row['date_expiration'] as String);
    return (now ?? DateTime.now()).isAfter(expiration);
  }
}
