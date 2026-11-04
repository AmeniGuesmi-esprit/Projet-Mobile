import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/service_badge.dart';

/// Landing palette (purple → orange brand, pastel service colours).
class _C {
  const _C._();

  static const Color ink = Color(0xFF2B1A6B); // body titles
  static const Color purple = Color(0xFF7B2FF7);
  static const Color violet = Color(0xFF6A23C9); // « un seul endroit ! »
  static const Color orange = Color(0xFFF7931E);
  static const Color orangeDeep = Color(0xFFF26A1B);
  static const Color lavender = Color(0xFFEFE8FD);
}

/// Colours of one service pill / bubble.
class _ServiceStyle {
  const _ServiceStyle(
    this.type,
    this.icon, {
    required this.text,
    required this.iconColor,
    required this.fill,
    required this.border,
    this.iconTurn = 0,
  });

  final ServiceType type;
  final IconData icon;
  final Color text;
  final Color iconColor;
  final Color fill;
  final Color border;

  /// Rotation applied to the icon (the dumbbell glyph is diagonal).
  final double iconTurn;

  Widget iconWidget(double size) => Transform.rotate(
    angle: iconTurn,
    child: Icon(icon, size: size, color: iconColor),
  );

  String get label => ServiceMeta.of(type).label;
}

const _ecoRoute = _ServiceStyle(
  ServiceType.ecoRoute,
  Icons.directions_car_filled_rounded,
  text: Color(0xFF3346C9),
  iconColor: Color(0xFF3F51D9),
  fill: Color(0xFFE6EBFF),
  border: Color(0xFFB9C4F5),
);
const _foodSave = _ServiceStyle(
  ServiceType.foodSave,
  Icons.restaurant_rounded,
  text: Color(0xFFD9600C),
  iconColor: Color(0xFFF57C1F),
  fill: Color(0xFFFFF0E1),
  border: Color(0xFFFFCB97),
);
const _teleDoc = _ServiceStyle(
  ServiceType.teleDoc,
  Icons.medical_services_rounded,
  text: Color(0xFFD42A44),
  iconColor: Color(0xFFE8384F),
  fill: Color(0xFFFFE8EC),
  border: Color(0xFFF8B4C0),
);
const _coachProche = _ServiceStyle(
  ServiceType.coachProche,
  Icons.fitness_center_rounded,
  text: Color(0xFF6A23C9),
  iconColor: Color(0xFF7B2FD6),
  fill: Color(0xFFF1E6FF),
  border: Color(0xFFD3B5F7),
  iconTurn: -math.pi / 4,
);
const _serviceNow = _ServiceStyle(
  ServiceType.serviceNow,
  Icons.build_rounded,
  text: Color(0xFF2E7D32),
  iconColor: Color(0xFF3E9142),
  fill: Color(0xFFEAF6E2),
  border: Color(0xFFBFE0A9),
);

/// First screen when nobody is signed in: logo, tagline, services,
/// « Commencer » (login) and « Créer un compte ».
class LandingScreen extends StatefulWidget {
  const LandingScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barHeight = 124 + bottomInset;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _BackgroundPainter()),
              ),
            ),
            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, c) {
                  // The illustration takes what is left above the bottom bar
                  // (it slides a little under the bar's wave, like the mockup).
                  final illustration = (c.maxHeight - 470 - barHeight).clamp(
                    150.0,
                    320.0,
                  );
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, barHeight),
                    child: Column(
                      children: [
                        const _Brand(),
                        const SizedBox(height: 10),
                        const _Tagline(),
                        const SizedBox(height: 14),
                        const _SectionTitle('Nos services'),
                        const SizedBox(height: 14),
                        _ServiceGrid(onTap: widget.onLogin),
                        SizedBox(
                          height: illustration,
                          child: _Illustration(animation: _float),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: barHeight,
              child: _BottomBar(
                onLogin: widget.onLogin,
                onRegister: widget.onRegister,
                bottomInset: bottomInset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ brand

/// Logo, then the « Proxi » + « Life » wordmark.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 44,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
    );
    return Semantics(
      header: true,
      label: 'ProxiLife',
      child: ExcludeSemantics(
        child: Column(
          children: [
            const _Logo(size: 84),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Proxi',
                  style: style.copyWith(color: AppColors.primaryDeep),
                ),
                Text('Life', style: style.copyWith(color: AppColors.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// App logo: green rounded square with a white leaf.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(size * 0.24),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.30),
          blurRadius: size * 0.25,
          offset: Offset(0, size * 0.1),
        ),
      ],
    ),
    child: Icon(Icons.eco_rounded, color: Colors.white, size: size * 0.42),
  );
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontFamily: 'Inter',
      fontSize: 19,
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: _C.ink,
    );
    return Column(
      children: [
        const Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: 'Simplifiez votre quotidien,\ntout en '),
              TextSpan(
                text: 'un seul endroit !',
                style: TextStyle(color: _C.violet, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        Transform.translate(
          offset: const Offset(34, 0),
          child: const SizedBox(
            width: 150,
            height: 10,
            child: CustomPaint(painter: _SwooshPainter()),
          ),
        ),
      ],
    );
  }
}

class _SwooshPainter extends CustomPainter {
  const _SwooshPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.8)
        ..quadraticBezierTo(
          size.width * 0.5,
          -size.height * 0.2,
          size.width,
          size.height * 0.6,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(colors: [_C.orangeDeep, _C.orange])
            .createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    Widget line() =>
        Expanded(child: Container(height: 1.6, color: const Color(0xFFC9C3F3)));
    return Row(
      children: [
        const SizedBox(width: 12),
        line(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: _C.ink,
            ),
          ),
        ),
        line(),
        const SizedBox(width: 12),
      ],
    );
  }
}

// --------------------------------------------------------------- services

/// 2 + 2 + 1 pills, like the mockup. Tapping one leads to the login.
class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 12, height: 12);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _ServicePill(_ecoRoute, onTap: onTap)),
            gap,
            Expanded(child: _ServicePill(_foodSave, onTap: onTap)),
          ],
        ),
        gap,
        Row(
          children: [
            Expanded(flex: 13, child: _ServicePill(_teleDoc, onTap: onTap)),
            gap,
            Expanded(flex: 11, child: _ServicePill(_coachProche, onTap: onTap)),
          ],
        ),
        gap,
        FractionallySizedBox(
          widthFactor: 0.54,
          child: _ServicePill(_serviceNow, onTap: onTap),
        ),
      ],
    );
  }
}

class _ServicePill extends StatelessWidget {
  const _ServicePill(this.style, {required this.onTap});

  final _ServiceStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
      side: BorderSide(color: style.border, width: 1.6),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: style.iconColor.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: style.fill,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 12),
                style.iconWidget(26),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      style.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: style.text,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 22, color: style.text),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- illustration

/// Purple phone in the middle, the five service bubbles floating around
/// it, a lavender city on the right.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.animation});

  final Animation<double> animation;

  // (style, x, y as fractions of the visible area, tilt in radians)
  static const _bubbles = [
    (_ecoRoute, 0.03, 0.04, -0.18),
    (_teleDoc, 0.08, 0.56, -0.12),
    (_foodSave, 0.72, 0.0, 0.12),
    (_coachProche, 0.84, 0.36, 0.16),
    (_serviceNow, 0.70, 0.70, -0.10),
  ];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final phoneH = h * 0.95;
          final phoneW = phoneH * 0.52;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value * 2 * math.pi;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Soft lavender halo + city.
                  Positioned(
                    left: w / 2 - h * 0.55,
                    top: h * 0.05,
                    child: Container(
                      width: h * 1.1,
                      height: h * 1.1,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF3EEFD),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: CustomPaint(painter: _CityPainter()),
                  ),
                  // Phone.
                  Positioned(
                    left: w / 2 - phoneW / 2,
                    top: h * 0.10 + math.sin(t) * 3,
                    child: Transform.rotate(
                      angle: 0.2,
                      child: _Phone(width: phoneW, height: phoneH),
                    ),
                  ),
                  // Orange sparkles above the phone.
                  Positioned(
                    left: w / 2 + phoneW * 0.15,
                    top: 0,
                    child: const SizedBox(
                      width: 60,
                      height: 50,
                      child: CustomPaint(painter: _PhoneSparkPainter()),
                    ),
                  ),
                  for (var i = 0; i < _bubbles.length; i++)
                    Positioned(
                      left: _bubbles[i].$2 * w,
                      top: _bubbles[i].$3 * h + math.sin(t + i * 1.3) * 5,
                      child: Transform.rotate(
                        angle: _bubbles[i].$4 + math.sin(t + i) * 0.05,
                        child: _Bubble(_bubbles[i].$1),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9B4DFF), Color(0xFF5B1FCF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(width * 0.2),
        boxShadow: [
          BoxShadow(
            color: _C.purple.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Logo(size: width * 0.42),
            SizedBox(height: height * 0.05),
            for (final s in [_ecoRoute, _foodSave, _teleDoc])
              Container(
                margin: EdgeInsets.only(top: height * 0.03),
                width: width * 0.62,
                height: height * 0.06,
                decoration: BoxDecoration(
                  color: s.fill,
                  border: Border.all(color: s.border),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.style);

  final _ServiceStyle style;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: style.fill,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [
        BoxShadow(
          color: style.iconColor.withValues(alpha: 0.25),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: style.iconWidget(27),
  );
}

class _PhoneSparkPainter extends CustomPainter {
  const _PhoneSparkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _C.orange
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.15),
      Offset(size.width * 0.25, size.height * 0.55),
      p,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, size.height * 0.2),
      Offset(size.width * 0.42, size.height * 0.62),
      p,
    );
    canvas.drawLine(
      Offset(size.width * 0.9, size.height * 0.5),
      Offset(size.width * 0.55, size.height * 0.8),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CityPainter extends CustomPainter {
  const _CityPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = const Color(0xFFE9E1FC);
    final window = Paint()..color = Colors.white.withValues(alpha: 0.7);
    const buildings = [
      (0.78, 0.55, 0.07),
      (0.85, 0.80, 0.08),
      (0.92, 0.62, 0.08),
      (0.71, 0.38, 0.06),
    ];
    for (final (x, hf, wf) in buildings) {
      final r = Rect.fromLTWH(
        size.width * x,
        size.height * (1 - hf),
        size.width * wf,
        size.height * hf,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          r,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        body,
      );
      for (var y = r.top + 10; y < r.bottom - 10; y += 16) {
        canvas.drawRect(Rect.fromLTWH(r.left + r.width * 0.3, y, 4, 6), window);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ------------------------------------------------------------ bottom bar

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onLogin,
    required this.onRegister,
    required this.bottomInset,
  });

  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _StartButton(
                  key: const ValueKey('landing-login'),
                  onPressed: onLogin,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const ValueKey('landing-register'),
                onPressed: onRegister,
                child: const Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _C.ink,
                    ),
                    children: [
                      TextSpan(text: 'Pas encore de compte ? '),
                      TextSpan(
                        text: 'Créer un compte',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      label: 'Commencer',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.primaryDeep,
              AppColors.primary,
              Color(0xFF2FA97A),
            ],
          ),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: const SizedBox(
              height: 56,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Commencer',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 14),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastel blobs in the corners (purple, peach, green), like the mockup.
class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint fill(List<Color> colors, Rect r) => Paint()
      ..shader = LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r);

    // Top left: peach under purple.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w * 0.36, 0)
        ..cubicTo(w * 0.30, h * 0.12, w * 0.14, h * 0.18, w * 0.05, h * 0.27)
        ..lineTo(0, h * 0.30)
        ..close(),
      fill(const [
        Color(0xFFFFD2A8),
        Color(0xFFFFE6CF),
      ], Rect.fromLTWH(0, 0, w * 0.4, h * 0.3)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w * 0.42, 0)
        ..cubicTo(w * 0.34, h * 0.06, w * 0.18, h * 0.06, w * 0.12, h * 0.12)
        ..cubicTo(w * 0.07, h * 0.17, w * 0.03, h * 0.19, 0, h * 0.21)
        ..close(),
      fill(const [
        Color(0xFFCFA6F5),
        Color(0xFFE8D6FB),
      ], Rect.fromLTWH(0, 0, w * 0.42, h * 0.21)),
    );
    // Top right: green.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.72, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * 0.14)
        ..cubicTo(w * 0.90, h * 0.12, w * 0.84, h * 0.05, w * 0.72, 0)
        ..close(),
      fill(const [
        Color(0xFFE6F3DA),
        Color(0xFFCBE6B5),
      ], Rect.fromLTWH(w * 0.7, 0, w * 0.3, h * 0.14)),
    );
    canvas.drawCircle(
      Offset(w * 0.89, h * 0.135),
      w * 0.028,
      Paint()..color = const Color(0xFFCDE8BC),
    );
    // Right: peach half-circle.
    canvas.drawCircle(
      Offset(w * 1.02, h * 0.26),
      w * 0.09,
      Paint()..color = const Color(0xFFFFDDC2),
    );
    // Left: green blob.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.27)
        ..cubicTo(w * 0.12, h * 0.28, w * 0.12, h * 0.37, 0, h * 0.40)
        ..close(),
      Paint()..color = const Color(0xFFDDEFD0),
    );
    // Bottom: lavender left, peach right.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.56)
        ..cubicTo(w * 0.25, h * 0.55, w * 0.3, h * 0.75, 0, h * 0.80)
        ..close(),
      Paint()..color = _C.lavender,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w, h * 0.70)
        ..cubicTo(w * 0.80, h * 0.72, w * 0.78, h * 0.85, w, h * 0.90)
        ..close(),
      Paint()..color = const Color(0xFFFFE6D3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
