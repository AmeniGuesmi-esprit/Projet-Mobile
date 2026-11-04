import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:proxilife_shared/proxilife_shared.dart';

import '../api_error.dart';

/// A stored symptom photo, ready to be served.
class TeledocPhoto {
  const TeledocPhoto(this.bytes, this.contentType);

  final List<int> bytes;
  final String contentType;
}

/// Stores symptom photos on disk (`server/uploads/teledoc/`, git-ignored).
///
/// Security (CONCEPTION.md, D6):
/// - size checked before and after base64 decoding (2 MB max);
/// - the real file type is checked with its magic bytes (JPEG / PNG only),
///   never trusted from a client-provided name or MIME type;
/// - files get a random name (16 secure random bytes), so a stored name can
///   neither be guessed nor used for path traversal.
class TeledocPhotoStore {
  TeledocPhotoStore(this.directory);

  final String directory;

  static final RegExp _storedName = RegExp(r'^[0-9a-f]{32}\.(jpg|png)$');
  static const List<int> _jpegMagic = [0xFF, 0xD8, 0xFF];
  static const List<int> _pngMagic = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ];

  /// Validates and stores a base64 photo (a `data:image/...;base64,` prefix
  /// is tolerated). Returns the stored file name.
  Future<String> save(String base64Data) async {
    var data = base64Data.trim();
    final comma = data.indexOf(',');
    if (data.startsWith('data:') && comma > 0) {
      data = data.substring(comma + 1);
    }
    data = data.replaceAll(RegExp(r'\s'), '');

    // Reject oversized payloads before allocating the decoded bytes.
    final maxEncoded = ((TeledocPhotoRules.maxBytes + 2) ~/ 3) * 4;
    if (data.length > maxEncoded) throw _tooLarge();

    final List<int> bytes;
    try {
      bytes = base64.decode(data);
    } on FormatException {
      throw ApiError.badRequest('Photo invalide : encodage base64 attendu');
    }
    if (bytes.isEmpty) {
      throw ApiError.badRequest('Photo vide');
    }
    if (bytes.length > TeledocPhotoRules.maxBytes) throw _tooLarge();

    final extension = detectExtension(bytes);
    if (extension == null) {
      throw ApiError.badRequest(
          'Format de photo non accepté : JPEG ou PNG uniquement');
    }

    final random = Random.secure();
    final name = '${List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join()}.$extension';
    await Directory(directory).create(recursive: true);
    await File(p.join(directory, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// `jpg` / `png` from the file signature, `null` for anything else.
  static String? detectExtension(List<int> bytes) {
    bool startsWith(List<int> magic) {
      if (bytes.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith(_jpegMagic)) return 'jpg';
    if (startsWith(_pngMagic)) return 'png';
    return null;
  }

  /// Returns the photo, or `null` if [name] is not a valid stored name or the
  /// file is missing.
  Future<TeledocPhoto?> read(String name) async {
    if (!_storedName.hasMatch(name)) return null;
    final file = File(p.join(directory, name));
    if (!await file.exists()) return null;
    final contentType = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
    return TeledocPhoto(await file.readAsBytes(), contentType);
  }

  /// Best-effort deletion: a leftover file must never fail a user action.
  Future<void> delete(String? name) async {
    if (name == null || !_storedName.hasMatch(name)) return;
    try {
      final file = File(p.join(directory, name));
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      developer.log('Photo non supprimée : $name',
          error: e, name: 'teledoc.photo');
    }
  }

  /// Deletes stored photos that no request references any more (account
  /// deleted by cascade, crash between save and insert). Only files with a
  /// stored-photo name, older than [grace], are considered: a photo being
  /// saved right now is never touched. Returns the number deleted.
  Future<int> purgeOrphans(
    Set<String> referenced, {
    Duration grace = const Duration(hours: 1),
    DateTime? now,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return 0;
    final limit = (now ?? DateTime.now()).subtract(grace);
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!_storedName.hasMatch(name) || referenced.contains(name)) continue;
      if ((await entity.lastModified()).isAfter(limit)) continue;
      await delete(name);
      deleted++;
    }
    return deleted;
  }

  ApiError _tooLarge() => ApiError.badRequest(
      'Photo trop volumineuse : ${TeledocPhotoRules.maxBytes ~/ (1024 * 1024)} '
      'Mo maximum');
}
