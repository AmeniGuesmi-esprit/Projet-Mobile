import 'package:geolocator/geolocator.dart';

/// User-facing (French) location error.
class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => 'LocationException: $message';
}

/// Thin wrapper over `geolocator`. The app always asks for the user's explicit
/// consent (a dialog) BEFORE calling [requestPermission].
class DeviceLocationService {
  const DeviceLocationService();

  /// True when the system permission has not been granted yet and can still
  /// be requested (so the app must first explain why it needs the position).
  Future<bool> needsPermissionPrompt() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine;
  }

  /// Shows the system permission dialog.
  Future<void> requestPermission() async {
    await Geolocator.requestPermission();
  }

  /// Current GPS position. Throws [LocationException] with a clear message.
  Future<({double latitude, double longitude})> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
          'La localisation est désactivée sur votre téléphone');
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Localisation bloquée : autorisez-la dans les réglages de l\'application');
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationException('Autorisation de localisation refusée');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } on Exception {
      throw const LocationException('Position introuvable, réessayez');
    }
  }
}
