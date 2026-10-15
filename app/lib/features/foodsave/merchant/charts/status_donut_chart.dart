import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'chart_format.dart';

/// One donut segment: a reservation status with its count and colour.
class DonutSegment {
  const DonutSegment({
    required this.status,
    required this.value,
    required this.color,
  });

  final ReservationStatus status;
  final int value;
  final Color color;

  String get label => status.label;
}

/// Animated donut of reservations by status with the pickup rate in the
/// centre and a legend (label + value + share, never colour alone).
///
/// Colours: retiré = success, à retirer = FoodSave, expiré = warning,
/// annulé = error tint.
class StatusDonutChart extends StatefulWidget {
  const StatusDonutChart({
    super.key,
    required this.parStatut,
    required this.tauxRetrait,
    this.diameter = 168,
  });

  /// Counts keyed by [ReservationStatus.apiValue].
  final Map<String, int> parStatut;

  /// Picked-up / (picked-up + expired), 0–100.
  final int tauxRetrait;
  final double diameter;

  static const Duration sweepDuration = Duration(milliseconds: 700);

  static Color colorOf(ReservationStatus s) => switch (s) {
        ReservationStatus.retire => AppColors.success,
        ReservationStatus.enAttente => AppColors.moduleFoodSave,
        ReservationStatus.expire => AppColors.warning,
        ReservationStatus.annule => AppColors.error.withValues(alpha: 0.55),
      };

  /// Display order: outcomes first, then pending, then failures.
  static const List<ReservationStatus> order = [
    ReservationStatus.retire,
    ReservationStatus.enAttente,
    ReservationStatus.expire,
    ReservationStatus.annule,
  ];

  static List<DonutSegment> segmentsOf(Map<String, int> parStatut) => [
        for (final s in order)
          DonutSegment(
              status: s, value: parStatut[s.apiValue] ?? 0, color: colorOf(s)),
      ];

  /// Screen-reader summary of the whole chart.
  static String semanticsSummary(Map<String, int> parStatut, int tauxRetrait) {
    final segments = segmentsOf(parStatut);
    final total = segments.fold<int>(0, (a, s) => a + s.value);
    if (total == 0) {
      return 'Réservations par statut : aucune réservation pour le moment';
    }
    final parts = segments.map((s) => '${s.label} ${s.value}').join(', ');
    return 'Réservations par statut : $parts. '
        'Taux de retrait ${ChartFormat.percent(tauxRetrait)}';
  }

  @override
  State<StatusDonutChart> createState() => _StatusDonutChartState();
}

class _StatusDonutChartState extends State<StatusDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: StatusDonutChart.sweepDuration);
  late final CurvedAnimation _sweep =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(StatusDonutChart old) {
    super.didUpdateWidget(old);
    if (!_sameCounts(old.parStatut, widget.parStatut)) {
      _controller.value = 0;
      _start();
    }
  }

  static bool _sameCounts(Map<String, int> a, Map<String, int> b) {
    for (final s in StatusDonutChart.order) {
      if ((a[s.apiValue] ?? 0) != (b[s.apiValue] ?? 0)) return false;
    }
    return true;
  }

  void _start() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = StatusDonutChart.segmentsOf(widget.parStatut);
    final total = segments.fold<int>(0, (a, s) => a + s.value);
    final theme = Theme.of(context).textTheme;

    final donut = SizedBox.square(
      dimension: widget.diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: StatusDonutPainter(
                  sweep: _sweep,
                  segments: segments,
                  strokeWidth: widget.diameter * 0.13,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(widget.diameter * 0.18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total == 0 ? '–' : ChartFormat.percent(widget.tauxRetrait),
                    style: theme.headlineMedium?.copyWith(
                        color: AppColors.moduleFoodSaveDeep,
                        fontWeight: FontWeight.w800),
                  ),
                  Text('taux de retrait', style: theme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in segments)
          _LegendRow(segment: s, total: total),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Aucune réservation pour le moment : publiez un panier pour '
              'commencer.',
              style: theme.bodySmall,
            ),
          ),
      ],
    );

    return Semantics(
      container: true,
      label: StatusDonutChart.semanticsSummary(
          widget.parStatut, widget.tauxRetrait),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Side by side when there is room, stacked otherwise (large
            // text / narrow phones).
            final wide = constraints.maxWidth >= widget.diameter + 200;
            if (wide) {
              return Row(
                children: [
                  donut,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: legend),
                ],
              );
            }
            return Column(
              children: [
                donut,
                const SizedBox(height: AppSpacing.md),
                legend,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.segment, required this.total});

  final DonutSegment segment;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final share = total == 0 ? 0 : segment.value * 100 / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: segment.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(segment.label,
                style: theme.bodyMedium?.copyWith(color: AppColors.text)),
          ),
          Text('${segment.value}',
              style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(
            width: 52,
            child: Text(
              ChartFormat.percent(share),
              textAlign: TextAlign.right,
              style: theme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the donut ring. Repaints on every [sweep] tick, otherwise only
/// when segments change.
class StatusDonutPainter extends CustomPainter {
  StatusDonutPainter({
    required this.sweep,
    required this.segments,
    required this.strokeWidth,
  }) : super(repaint: sweep);

  final Animation<double> sweep;
  final List<DonutSegment> segments;
  final double strokeWidth;

  static const double _gap = 0.035; // radians between segments

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final rect =
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Track.
    canvas.drawArc(rect, 0, math.pi * 2, false,
        paint..color = AppColors.outlineSoft);

    final total = segments.fold<int>(0, (a, s) => a + s.value);
    if (total == 0) return;
    final visible = segments.where((s) => s.value > 0).toList();
    final gap = visible.length > 1 ? _gap : 0.0;
    final limit = math.pi * 2 * sweep.value;

    var start = -math.pi / 2;
    var drawn = 0.0;
    for (final s in visible) {
      final full = math.pi * 2 * s.value / total;
      final arc = math.min(full, limit - drawn);
      if (arc <= 0) break;
      final sweepAngle = math.max(0.0, arc - gap);
      if (sweepAngle > 0) {
        canvas.drawArc(
            rect, start + gap / 2, sweepAngle, false, paint..color = s.color);
      }
      start += full;
      drawn += full;
    }
  }

  @override
  bool shouldRepaint(StatusDonutPainter old) {
    if (old.sweep != sweep || old.strokeWidth != strokeWidth) return true;
    if (old.segments.length != segments.length) return true;
    for (var i = 0; i < segments.length; i++) {
      if (old.segments[i].value != segments[i].value ||
          old.segments[i].color != segments[i].color) {
        return true;
      }
    }
    return false;
  }
}
