import 'package:local_auth/local_auth.dart';

/// Result of a biometric confirmation request.
enum BiometricResult {
  /// The user successfully proved their identity.
  granted,

  /// The user cancelled or failed the prompt: abort the action silently.
  denied,

  /// No biometrics available on this device: proceed without blocking.
  unavailable,
}

/// Confirms sensitive payment actions with biometrics (fingerprint / face).
class BiometricGuard {
  BiometricGuard({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// Asks for a biometric confirmation with [reason] displayed in the
  /// system dialog.
  Future<BiometricResult> confirm({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.granted : BiometricResult.denied;
    } on LocalAuthException {
      return BiometricResult.unavailable;
    }
  }
}
