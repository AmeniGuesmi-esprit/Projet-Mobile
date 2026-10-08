import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Password hashing with PBKDF2-HMAC-SHA256 (implemented on top of
/// package:crypto's HMAC). Stored format:
/// `pbkdf2$<iterations>$<salt b64>$<hash b64>`.
class PasswordHasher {
  const PasswordHasher({this.iterations = defaultIterations});

  static const int defaultIterations = 210000;
  static const int saltLength = 16;
  static const int hashLength = 32;

  final int iterations;

  String hashPassword(String password, {int? iterationOverride}) {
    final iterations = iterationOverride ?? this.iterations;
    final salt = Uint8List.fromList(
      List.generate(saltLength, (_) => Random.secure().nextInt(256)),
    );
    final hash = pbkdf2(password, salt, iterations, hashLength);
    return 'pbkdf2\$$iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  bool verifyPassword(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null) return false;
    final salt = base64Decode(parts[2]);
    final expected = base64Decode(parts[3]);
    final actual = pbkdf2(password, salt, iterations, expected.length);
    return _constantTimeEquals(actual, expected);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// One-way PBKDF2-HMAC-SHA256. [blockIndex] encoded big-endian, as in RFC 2898.
Uint8List pbkdf2(String password, List<int> salt, int iterations, int dkLen) {
  final passwordBytes = utf8.encode(password);
  final hmacLength = sha256.convert(const []).bytes.length;
  final blockCount = (dkLen / hmacLength).ceil();
  final output = <int>[];
  for (var block = 1; block <= blockCount; block++) {
    var u = Hmac(sha256, passwordBytes)
        .convert([...salt, (block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff])
        .bytes;
    var t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = Hmac(sha256, passwordBytes).convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.addAll(t);
  }
  return Uint8List.fromList(output.sublist(0, dkLen));
}

/// SHA-256 hash used for session tokens and verification codes stored at
/// rest (never stored in plain text).
String sha256HexOf(String input) =>
    sha256.convert(utf8.encode(input)).toString();
