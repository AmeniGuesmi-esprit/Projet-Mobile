import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Size of the square scan window for a given viewport.
Rect scanWindowFor(Size size) {
  final side = (size.shortestSide * 0.68).clamp(180.0, 300.0);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.42),
    width: side,
    height: side,
  );
}

/// Dimmed camera overlay with a rounded cut-out and FoodSave corner accents.
class ScanFrameOverlay extends StatelessWidget {
  const ScanFrameOverlay({super.key, this.busy = false});

  /// Shows a progress bar inside the frame while a code is being checked.
  final bool busy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final window = scanWindowFor(constraints.biggest);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _FramePainter(window)),
              ),
              Positioned(
                left: window.left,
                width: window.width,
                top: window.bottom + AppSpacing.md,
                child: Text(
                  busy
                      ? 'Vérification en cours…'
                      : 'Placez le QR code du client dans le cadre',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
              if (busy)
                Positioned(
                  left: window.left + AppSpacing.lg,
                  width: window.width - 2 * AppSpacing.lg,
                  top: window.center.dy - 2,
                  child: const LinearProgressIndicator(
                    minHeight: 4,
                    color: AppColors.accent,
                    backgroundColor: Colors.white24,
                  ),
                ),
            ],
          );
        },
      );
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout =
        RRect.fromRectAndRadius(window, const Radius.circular(AppRadius.lg));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    // Corner accents.
    const len = 34.0;
    const r = AppRadius.lg;
    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.moduleFoodSave;
    final l = window.left, t = window.top, rt = window.right, b = window.bottom;
    canvas
      ..drawPath(
          Path()
            ..moveTo(l, t + len)
            ..lineTo(l, t + r)
            ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
            ..lineTo(l + len, t),
          accent)
      ..drawPath(
          Path()
            ..moveTo(rt - len, t)
            ..lineTo(rt - r, t)
            ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
            ..lineTo(rt, t + len),
          accent)
      ..drawPath(
          Path()
            ..moveTo(rt, b - len)
            ..lineTo(rt, b - r)
            ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
            ..lineTo(rt - len, b),
          accent)
      ..drawPath(
          Path()
            ..moveTo(l + len, b)
            ..lineTo(l + r, b)
            ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
            ..lineTo(l, b - len),
          accent);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.window != window;
}
