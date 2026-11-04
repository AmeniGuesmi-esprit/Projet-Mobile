import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../domain/teledoc_location.dart';

/// [TeledocLocationProvider] backed by `geolocator`. High accuracy (GPS):
/// a one-shot read costs little battery, and medium accuracy relies on the
/// network provider only, which the Android emulator does not simulate.
class GeolocatorLocationProvider implements TeledocLocationProvider {
  const GeolocatorLocationProvider();

  @override
  Future<TeledocPosition> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const TeledocLocationException(
        TeledocLocationIssue.serviceDisabled,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const TeledocLocationException(TeledocLocationIssue.denied);
      case LocationPermission.deniedForever:
        throw const TeledocLocationException(
          TeledocLocationIssue.deniedForever,
        );
      case LocationPermission.whileInUse:
      case LocationPermission.always:
      case LocationPermission.unableToDetermine:
        break;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return TeledocPosition(position.latitude, position.longitude);
    } on TimeoutException {
      // No fix in time (indoors): the last known position is good enough.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return TeledocPosition(last.latitude, last.longitude);
      throw const TeledocLocationException(TeledocLocationIssue.unavailable);
    } on LocationServiceDisabledException {
      throw const TeledocLocationException(
        TeledocLocationIssue.serviceDisabled,
      );
    }
  }

  @override
  Future<void> openSettings(TeledocLocationIssue issue) async {
    if (issue == TeledocLocationIssue.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
