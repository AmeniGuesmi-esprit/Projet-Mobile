import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Parsed, signature-checked QR payload.
class CoachQrPayload {
  const CoachQrPayload(this.reservationId, this.nonce);

  final int reservationId;
  final String nonce;
}

/// Signed, opaque QR tokens for CoachProche presence checks.
///
/// Format: `CP1.<reservationId>.<nonce>.<sig>` where
/// - nonce = 16 random bytes, base64url without padding;
/// - sig   = base64url (no padding) of HMAC-SHA256(secret, `CP1.<id>.<nonce>`).
///
/// The secret (32 random bytes) is created once and stored in
/// `coach_parametre`. A token carries no personal data and is only valid
/// while it matches the booking's current `code_qr_nonce`.
class CoachQrTokenService {
  CoachQrTokenService(this.db);

  final Database db;

  static const String version = 'CP1';
  static const String secretKey = 'qr_secret';
  static const int maxTokenLength = 256;

  static final Expando<Future<List<int>>> _secrets = Expando('coach_qr_secret');
  static final RegExp _nonceRe = RegExp(r'^[A-Za-z0-9_-]{22}$');
  static final RegExp _sigRe = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final RegExp _idRe = RegExp(r'^[1-9][0-9]{0,15}$');

  /// A fresh random nonce (16 bytes, base64url, no padding -> 22 chars).
  static String newNonce() =>
      _b64(List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  /// Signs `CP1.<reservationId>.<nonce>`.
  Future<String> sign(int reservationId, String nonce) async {
    final body = '$version.$reservationId.$nonce';
    return '$body.${await _signature(body)}';
  }

  /// The payload when [token] is well-formed and correctly signed, `null`
  /// otherwise (forged, truncated, wrong version...).
  Future<CoachQrPayload?> verify(String token) async {
    final t = token.trim();
    if (t.isEmpty || t.length > maxTokenLength) return null;
    final parts = t.split('.');
    if (parts.length != 4 || parts[0] != version) return null;
    if (!_idRe.hasMatch(parts[1]) ||
        !_nonceRe.hasMatch(parts[2]) ||
        !_sigRe.hasMatch(parts[3])) {
      return null;
    }
    final expected = await _signature('${parts[0]}.${parts[1]}.${parts[2]}');
    if (!_constantTimeEquals(expected, parts[3])) return null;
    final id = int.tryParse(parts[1]);
    if (id == null) return null;
    return CoachQrPayload(id, parts[2]);
  }

  Future<String> _signature(String body) async {
    final secret = await _secret();
    return _b64(Hmac(sha256, secret).convert(utf8.encode(body)).bytes);
  }

  Future<List<int>> _secret() {
    final cached = _secrets[db];
    if (cached != null) return cached;
    final loading = _loadOrCreateSecret(db);
    _secrets[db] = loading;
    // A failed load must not poison the cache.
    loading.catchError((Object _) {
      _secrets[db] = null;
      return const <int>[];
    });
    return loading;
  }

  static Future<List<int>> _loadOrCreateSecret(Database db) async {
    final candidate =
        _b64(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    // INSERT OR IGNORE: if two callers race, both read back the same value.
    await db.insert(
      'coach_parametre',
      {'cle': secretKey, 'valeur': candidate},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final rows = await db.query('coach_parametre',
        where: 'cle = ?', whereArgs: [secretKey]);
    final stored = rows.first['valeur'] as String;
    return base64Url.decode(base64Url.normalize(stored));
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static bool _constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    final n = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
