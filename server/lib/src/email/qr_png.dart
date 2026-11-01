import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:qr/qr.dart';

/// Renders [data] as a black-on-white QR code PNG (8-bit grayscale).
///
/// Same error-correction level as the app (`M`), so the e-mailed code and
/// the one shown on screen are interchangeable for the merchant's scanner.
/// [scale] = pixels per module, [margin] = quiet zone in modules (spec: 4).
Uint8List encodeQrPng(String data, {int scale = 8, int margin = 4}) {
  final image = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
  final modules = image.moduleCount;
  final size = (modules + 2 * margin) * scale;

  // Raw scanlines: filter byte 0 (none) + one byte per pixel.
  final raw = Uint8List((size + 1) * size);
  for (var y = 0; y < size; y++) {
    final row = y * (size + 1);
    final my = y ~/ scale - margin;
    for (var x = 0; x < size; x++) {
      final mx = x ~/ scale - margin;
      final dark = my >= 0 &&
          mx >= 0 &&
          my < modules &&
          mx < modules &&
          image.isDark(my, mx);
      raw[row + 1 + x] = dark ? 0x00 : 0xFF;
    }
  }

  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // color type: grayscale
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', ZLibCodec(level: 9).encode(raw));
  _chunk(out, 'IEND', const []);
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  out
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add(crc.buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
