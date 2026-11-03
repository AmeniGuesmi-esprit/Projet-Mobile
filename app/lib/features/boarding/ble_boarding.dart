import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

/// 16-bit service 0xB0A1 in its 128-bit form (advertised as 2 bytes).
const String boardingServiceUuid = '0000b0a1-0000-1000-8000-00805f9b34fb';

/// Manufacturer id reserved by the Bluetooth SIG for tests / internal use.
const int boardingManufacturerId = 0xFFFF;

/// Payload: 4 bytes trip id (big endian) + 8 ASCII characters of the code.
Uint8List boardingPayload(BoardingCodeDto c) {
  final bytes = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, c.tripId)).buffer.asUint8List())
    ..add(ascii.encode(c.code));
  return bytes.toBytes();
}

/// Returns the code when [data] is a boarding payload of [tripId].
String? codeFromBoardingPayload(List<int> data, int tripId) {
  if (data.length != 12) return null;
  final id = ByteData.sublistView(Uint8List.fromList(data), 0, 4).getUint32(0);
  if (id != tripId) return null;
  final code = ascii.decode(data.sublist(4), allowInvalid: true);
  return RegExp(r'^[0-9A-F]{8}$').hasMatch(code) ? code : null;
}

/// Driver side: broadcasts the current boarding code over Bluetooth LE.
/// Call [start] again each time the code is renewed.
///
/// The code travels in the manufacturer data, which Android and Windows can
/// advertise; iOS and macOS cannot, so a driver on iOS should use the QR code.
class BleBoardingBroadcaster {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  Future<void> start(BoardingCodeDto code) async {
    await stop();
    await _peripheral.start(
      advertiseData: AdvertiseDataCore(
        serviceUuid: boardingServiceUuid,
        manufacturerId: boardingManufacturerId,
        manufacturerData: boardingPayload(code),
      ),
    );
  }

  Future<void> stop() async {
    try {
      await _peripheral.stop();
    } catch (_) {
      // Already stopped.
    }
  }
}

/// Passenger side: looks for the driver's broadcast of [tripId] and returns
/// its code, or null when nothing was heard before the timeout.
class BleBoardingScanner {
  Future<String?> findCode(
    int tripId, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      throw StateError('Activez le Bluetooth');
    }
    final found = Completer<String?>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final data = r.advertisementData.manufacturerData[boardingManufacturerId];
        if (data == null || found.isCompleted) continue;
        final code = codeFromBoardingPayload(data, tripId);
        if (code != null) found.complete(code);
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(boardingServiceUuid)],
        timeout: timeout,
      );
      return await found.future
          .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }
}
