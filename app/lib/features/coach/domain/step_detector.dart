import 'dart:math' as math;

/// Counts steps from raw accelerometer samples (m/s²), without any plugin
/// dependency so it can be unit-tested.
///
/// Method: the gravity component is estimated with a slow low-pass filter and
/// removed from the magnitude of the acceleration. A step is counted each time
/// the remaining "dynamic" acceleration rises above [threshold], provided at
/// least [minInterval] elapsed since the previous step (this ignores the
/// bounce of a single footfall and fast hand shaking).
class StepDetector {
  StepDetector({
    this.threshold = 1.2,
    this.minInterval = const Duration(milliseconds: 300),
    this.gravitySmoothing = 0.98,
  });

  /// Minimum dynamic acceleration (m/s²) for a step.
  final double threshold;

  /// Shortest time between two steps.
  final Duration minInterval;

  /// Weight of the previous gravity estimate (closer to 1 = slower filter).
  final double gravitySmoothing;

  double? _gravity;
  bool _above = false;
  DateTime? _lastStep;
  int _steps = 0;

  /// Steps counted so far.
  int get steps => _steps;

  /// Forgets everything (new counting session).
  void reset() {
    _gravity = null;
    _above = false;
    _lastStep = null;
    _steps = 0;
  }

  /// Feeds one accelerometer sample taken at [at]. Returns `true` when this
  /// sample completes a new step.
  bool addSample(double x, double y, double z, DateTime at) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    final previous = _gravity ?? magnitude;
    final gravity =
        previous * gravitySmoothing + magnitude * (1 - gravitySmoothing);
    _gravity = gravity;
    final dynamicPart = magnitude - gravity;

    if (!_above && dynamicPart > threshold) {
      _above = true;
      final last = _lastStep;
      if (last == null || at.difference(last) >= minInterval) {
        _lastStep = at;
        _steps++;
        return true;
      }
    } else if (_above && dynamicPart < threshold / 2) {
      _above = false;
    }
    return false;
  }
}
