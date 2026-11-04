import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/money_text.dart';
import '../../widgets/foodsave_ui.dart';
import 'chart_format.dart';

/// Which series the weekly chart shows.
enum WeeklyMetric { reservations, revenus }

/// Animated bar chart of the last 7 days (oldest first).
///
/// - Bars: [AppColors.moduleFoodSave]; today's bar: [AppColors.accent].
/// - Value labels: [AppColors.moduleFoodSaveDeep] (AA on white).
/// - Grows in over 600 ms (easeOutCubic) and morphs between data/metric
///   changes; tap a bar for a tooltip (date, réservations, retraits, revenus).
class WeeklyBarChart extends StatefulWidget {
  const WeeklyBarChart({
    super.key,
    required this.days,
    this.metric = WeeklyMetric.reservations,
    this.today,
    this.height = 220,
  });

  final List<DailyStatDto> days;
  final WeeklyMetric metric;

  /// `YYYY-MM-DD` key of today (UTC). Defaults to the current UTC day.
  final String? today;
  final double height;

  static const Duration growDuration = Duration(milliseconds: 600);

  /// Screen-reader summary, e.g. "Réservations des 7 derniers jours :
  /// lundi 2, mardi 0, …".
  static String semanticsSummary(List<DailyStatDto> days, WeeklyMetric metric) {
    if (days.isEmpty) return 'Aucune donnée pour les 7 derniers jours';
    final parts = days.map((d) {
      final day = ChartFormat.weekdayLong(d.date);
      return metric == WeeklyMetric.reservations
          ? '$day ${d.reservations}'
          : '$day ${MoneyText.format(d.revenusCentimes)}';
    }).join(', ');
    final title = metric == WeeklyMetric.reservations
        ? 'Réservations des 7 derniers jours'
        : 'Revenus des 7 derniers jours';
    return '$title : $parts';
  }

  @override
  State<WeeklyBarChart> createState() => _WeeklyBarChartState();
}

class _WeeklyBarChartState extends State<WeeklyBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: WeeklyBarChart.growDuration);
  late final CurvedAnimation _progress =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  List<double> _from = const [];
  List<double> _to = const [];
  int? _selected;

  @override
  void initState() {
    super.initState();
    _to = _targetValues();
    _from = List.filled(_to.length, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(WeeklyBarChart old) {
    super.didUpdateWidget(old);
    if (old.days != widget.days || old.metric != widget.metric) {
      // Morph from what is currently on screen to the new values.
      final current = _currentValues();
      _to = _targetValues();
      _from = List.generate(
          _to.length, (i) => i < current.length ? current[i] : 0.0);
      if (_selected != null && _selected! >= _to.length) _selected = null;
      _controller.value = 0;
      _start();
    }
  }

  void _start() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  List<double> _targetValues() => widget.days
      .map((d) => (widget.metric == WeeklyMetric.reservations
              ? d.reservations
              : d.revenusCentimes)
          .toDouble())
      .toList(growable: false);

  List<double> _currentValues() {
    final t = _progress.value;
    return List.generate(
        _to.length,
        (i) => lerpDouble(i < _from.length ? _from[i] : 0, _to[i], t) ?? 0,
        growable: false);
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _todayKey => widget.today ?? ChartFormat.dayKey(DateTime.now());

  void _onTapUp(TapUpDetails details, double width) {
    final n = widget.days.length;
    if (n == 0) return;
    final index =
        (details.localPosition.dx / (width / n)).floor().clamp(0, n - 1);
    setState(() => _selected = _selected == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final todayIndex = days.indexWhere((d) => d.date == _todayKey);
    final scaler = ChartFormat.chartTextScaler(context);

    return Semantics(
      container: true,
      label: WeeklyBarChart.semanticsSummary(days, widget.metric),
      hint: 'Touchez une barre pour afficher le détail du jour',
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final selected = _selected;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTapUp(d, width),
                    child: ExcludeSemantics(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: WeeklyBarPainter(
                            progress: _progress,
                            from: _from,
                            to: _to,
                            labels: [
                              for (final d in days)
                                ChartFormat.weekdayShort(d.date)
                            ],
                            todayIndex: todayIndex,
                            selectedIndex: selected,
                            metric: widget.metric,
                            textScaler: scaler,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected != null && selected < days.length)
                  _positionedTooltip(days[selected], selected, width),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _positionedTooltip(DailyStatDto day, int index, double width) {
    const tooltipWidth = 184.0;
    final slot = width / widget.days.length;
    final centre = slot * index + slot / 2;
    final left = (centre - tooltipWidth / 2)
        .clamp(0.0, math.max(0.0, width - tooltipWidth)).toDouble();
    return Positioned(
      top: 0,
      left: left,
      width: math.min(tooltipWidth, width),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(index),
        tween: Tween(begin: 0, end: 1),
        duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
            ? Duration.zero
            : FoodSaveMotion.fast,
        curve: FoodSaveMotion.curve,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, (1 - t) * 6), child: child),
        ),
        child: _BarTooltip(
            day: day, onClose: () => setState(() => _selected = null)),
      ),
    );
  }
}

class _BarTooltip extends StatelessWidget {
  const _BarTooltip({required this.day, required this.onClose});

  final DailyStatDto day;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final r = day.reservations;
    final w = day.retraits;
    return Semantics(
      liveRegion: true,
      child: GestureDetector(
        onTap: onClose,
        child: Material(
          color: AppColors.surface,
          elevation: 3,
          shadowColor: AppColors.text.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: const BorderSide(color: AppColors.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs + 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ChartFormat.dayLabel(day.date),
                    style: theme.labelLarge?.copyWith(
                        color: AppColors.moduleFoodSaveDeep)),
                const SizedBox(height: AppSpacing.xxs),
                Text('$r réservation${r > 1 ? 's' : ''}',
                    style: theme.bodySmall),
                Text('$w retrait${w > 1 ? 's' : ''}', style: theme.bodySmall),
                Text('Revenus : ${MoneyText.format(day.revenusCentimes)}',
                    style: theme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints gridlines, rounded-top bars, value labels and weekday labels.
/// Repaints on every animation tick through [progress]; otherwise only when
/// its inputs change.
class WeeklyBarPainter extends CustomPainter {
  WeeklyBarPainter({
    required this.progress,
    required this.from,
    required this.to,
    required this.labels,
    required this.todayIndex,
    required this.selectedIndex,
    required this.metric,
    required this.textScaler,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final List<double> from;
  final List<double> to;
  final List<String> labels;
  final int todayIndex;
  final int? selectedIndex;
  final WeeklyMetric metric;
  final TextScaler textScaler;

  static const int _gridLines = 4;

  TextPainter _text(String text, double size, Color color,
      {FontWeight weight = FontWeight.w500}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size,
            fontWeight: weight,
            color: color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
  }

  /// Rounds the axis maximum up to a "nice" value.
  static double niceMax(double value) {
    if (value <= 0) return 4;
    final exponent = math.pow(10, (math.log(value) / math.ln10).floor());
    for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      final candidate = step * exponent;
      if (candidate >= value) return candidate.toDouble();
    }
    return 10.0 * exponent;
  }

  String _valueLabel(double v) => metric == WeeklyMetric.reservations
      ? v.round().toString()
      : ChartFormat.compactDinars(v.round());

  @override
  void paint(Canvas canvas, Size size) {
    final n = to.length;
    if (n == 0 || size.isEmpty) return;
    final t = progress.value;
    final values = List.generate(
        n, (i) => lerpDouble(i < from.length ? from[i] : 0, to[i], t) ?? 0);

    final labelHeight = textScaler.scale(12) + AppSpacing.xs + 4;
    final topPad = textScaler.scale(11) + AppSpacing.xs;
    final chartTop = topPad;
    final chartBottom = size.height - labelHeight;
    final chartHeight = math.max(0.0, chartBottom - chartTop);
    final maxTarget = to.fold<double>(0, math.max);
    final maxFrom = from.fold<double>(0, math.max);
    final axisMax = niceMax(math.max(maxTarget, maxFrom * (1 - t)));

    // Gridlines (outlineSoft) with a solid baseline.
    final grid = Paint()
      ..color = AppColors.outlineSoft
      ..strokeWidth = 1;
    for (var g = 0; g <= _gridLines; g++) {
      final y = chartBottom - chartHeight * g / _gridLines;
      grid.color = g == 0 ? AppColors.outline : AppColors.outlineSoft;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final slot = size.width / n;
    final barWidth = math.min(32.0, slot * 0.56);
    final radius = Radius.circular(math.min(8, barWidth / 2));

    for (var i = 0; i < n; i++) {
      final cx = slot * i + slot / 2;
      final v = values[i];
      final h = axisMax == 0
          ? 0.0
          : chartHeight * (v / axisMax).clamp(0.0, 1.0);
      final isToday = i == todayIndex;
      final isSelected = i == selectedIndex;

      if (isSelected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(slot * i + 2, chartTop, slot * (i + 1) - 2,
                chartBottom),
            const Radius.circular(AppRadius.sm),
          ),
          Paint()..color = AppColors.moduleFoodSaveSoft,
        );
      }

      if (h > 0.5) {
        final rect = Rect.fromLTRB(
            cx - barWidth / 2, chartBottom - h, cx + barWidth / 2, chartBottom);
        final rrect =
            RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius);
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = isToday ? AppColors.accent : AppColors.moduleFoodSave,
        );
        if (isSelected) {
          canvas.drawRRect(
            rrect,
            Paint()
              ..color = AppColors.moduleFoodSaveDeep
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }

      // Value label above the bar (deep orange: AA on white).
      if (to[i] > 0 && t > 0.15) {
        final label = _text(_valueLabel(v), 11, AppColors.moduleFoodSaveDeep,
            weight: FontWeight.w700);
        final y = math.max(0.0, chartBottom - h - label.height - 2);
        if (label.width <= slot) {
          label.paint(canvas, Offset(cx - label.width / 2, y));
        }
      }

      // Weekday label; today in bold deep orange.
      final day = _text(
        labels[i],
        12,
        isToday ? AppColors.moduleFoodSaveDeep : AppColors.textSecondaryStrong,
        weight: isToday ? FontWeight.w800 : FontWeight.w500,
      );
      if (day.width <= slot + 4) {
        day.paint(canvas,
            Offset(cx - day.width / 2, chartBottom + AppSpacing.xxs + 2));
      }
    }
  }

  @override
  bool shouldRepaint(WeeklyBarPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.to != to ||
      old.todayIndex != todayIndex ||
      old.selectedIndex != selectedIndex ||
      old.metric != metric ||
      old.textScaler != textScaler ||
      !_sameLabels(old.labels, labels);

  static bool _sameLabels(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
