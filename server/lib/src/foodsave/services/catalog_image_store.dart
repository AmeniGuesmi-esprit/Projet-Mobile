import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../api_error.dart';

/// Max accepted basket photo size (2 MB).
const int maxBasketImageBytes = 2 * 1024 * 1024;

/// Only names we generated ourselves: 16 random bytes hex + extension.
final RegExp basketImageNamePattern = RegExp(r'^[a-f0-9]{32}\.(jpg|png)$');

/// Stores basket photos on disk under [dir] with random, non-guessable names.
class BasketImageStore {
  BasketImageStore(this.dir);

  final String dir;
  static final Random _random = Random.secure();

  /// Returns the file extension (`jpg` / `png`) when [bytes] really are a
  /// JPEG / PNG matching [contentType], else throws a 400.
  static String validate(String? contentType, Uint8List bytes) {
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
    final isJpeg = bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var isPng = bytes.length > pngMagic.length;
    for (var i = 0; isPng && i < pngMagic.length; i++) {
      if (bytes[i] != pngMagic[i]) isPng = false;
    }
    if ((mime == 'image/jpeg' || mime == 'image/jpg') && isJpeg) return 'jpg';
    if (mime == 'image/png' && isPng) return 'png';
    throw ApiError.badRequest(
        'Format d\'image non pris en charge : envoyez une photo JPEG ou PNG');
  }

  /// Writes [bytes] under a fresh random name and returns that name.
  Future<String> save(Uint8List bytes, String extension) async {
    final directory = Directory(dir);
    if (!directory.existsSync()) await directory.create(recursive: true);
    final name = '${_randomHex(16)}.$extension';
    await File(p.join(dir, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Best-effort removal (a missing file is not an error).
  Future<void> delete(String? name) async {
    if (name == null || !basketImageNamePattern.hasMatch(name)) return;
    try {
      final file = File(p.join(dir, name));
      if (file.existsSync()) await file.delete();
    } catch (e, st) {
      developer.log('image delete failed',
          error: e, stackTrace: st, name: 'foodsave');
    }
  }

  /// The file for a validated [name], or null when absent / malformed.
  File? fileFor(String name) {
    if (!basketImageNamePattern.hasMatch(name)) return null;
    final file = File(p.join(dir, name));
    return file.existsSync() ? file : null;
  }

  static String contentTypeFor(String name) =>
      name.endsWith('.png') ? 'image/png' : 'image/jpeg';

  static String _randomHex(int bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// Reads at most [maxBasketImageBytes] from [stream]; 413 beyond that.
Future<Uint8List> readLimitedBytes(Stream<List<int>> stream,
    {int? declaredLength}) async {
  if (declaredLength != null && declaredLength > maxBasketImageBytes) {
    throw const ApiError(413, 'Image trop volumineuse (2 Mo maximum)');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    if (builder.length > maxBasketImageBytes) {
      throw const ApiError(413, 'Image trop volumineuse (2 Mo maximum)');
    }
  }
  if (builder.isEmpty) {
    throw ApiError.badRequest('Aucune image reçue');
  }
  return builder.takeBytes();
}
