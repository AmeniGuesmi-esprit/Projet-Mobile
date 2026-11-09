import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/features/coach/domain/step_detector.dart';

/// Feeds a vertical oscillation of [frequencyHz] / [amplitude] (m/s²) around
/// gravity, sampled at 25 Hz, and returns the number of steps counted.
int _simulate({
  required double frequencyHz,
  required double amplitude,
  required int seconds,
}) {
  final detector = StepDetector();
  final start = DateTime(2026, 11, 7, 10);
  const hz = 25;
  for (var i = 0; i < seconds * hz; i++) {
    final t = i / hz;
    final z = 9.81 + amplitude * math.sin(2 * math.pi * frequencyHz * t);
    detector.addSample(0.5, 0.2, z,
        start.add(Duration(milliseconds: (t * 1000).round())));
  }
  return detector.steps;
}

void main() {
  test('counts about two steps per second while walking', () {
    final steps = _simulate(frequencyHz: 2, amplitude: 3, seconds: 10);
    expect(steps, inInclusiveRange(17, 23));
  });

  test('counts nothing when the phone lies still', () {
    expect(_simulate(frequencyHz: 2, amplitude: 0, seconds: 10), 0);
  });

  test('ignores tiny vibrations', () {
    expect(_simulate(frequencyHz: 2, amplitude: 0.5, seconds: 10), 0);
  });

  test('reset starts a new count from zero', () {
    final detector = StepDetector();
    final start = DateTime(2026, 11, 7, 10);
    for (var i = 0; i < 100; i++) {
      final t = i / 25;
      detector.addSample(0, 0, 9.81 + 3 * math.sin(2 * math.pi * 2 * t),
          start.add(Duration(milliseconds: (t * 1000).round())));
    }
    expect(detector.steps, greaterThan(0));
    detector.reset();
    expect(detector.steps, 0);
  });
}
