import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../widgets/foodsave_ui.dart';
import 'booking_format.dart';

/// Circular countdown: the arc shrinks as [remaining] goes from [total] to
/// zero and changes colour (FoodSave → warning under 10 min → error under
/// 2 min). The arc glides between ticks unless animations are disabled.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 88,
    this.strokeWidth = 8,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final double strokeWidth;

  double get _progress {
    if (total.inMilliseconds <= 0) return remaining > Duration.zero ? 1 : 0;
    return (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final level = countdownLevel(remaining);
    final color = countdownColor(level);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final label = formatCountdown(remaining);
    return Semantics(
      label: 'Temps restant : ${spokenCountdown(remaining)}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _progress),
          duration: reduceMotion ? Duration.zero : FoodSaveMotion.medium,
          curve: FoodSaveMotion.curve,
          builder: (context, value, child) => CustomPaint(
            painter: CountdownRingPainter(
              progress: value,
              color: color,
              trackColor: AppColors.outlineSoft,
              strokeWidth: strokeWidth,
            ),
            child: child,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(strokeWidth + 4),
              child: FittedBox(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: countdownTextColor(level),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CountdownRingPainter extends CustomPainter {
  const CountdownRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(CountdownRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
