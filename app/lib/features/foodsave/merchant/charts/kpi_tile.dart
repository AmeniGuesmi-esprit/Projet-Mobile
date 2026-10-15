import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Dashboard KPI with an animated count-up (from the previous value to the
/// new one). Screen readers get the final value only.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.moduleFoodSave,
    this.format,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final int value;

  /// Icon / tint colour (a fill colour: never used for text).
  final Color color;

  /// Value formatter (e.g. [MoneyText.format]); defaults to the integer.
  final String Function(int value)? format;

  /// Accent background tint for the key value of the moment.
  final bool highlight;

  static const Duration countDuration = Duration(milliseconds: 900);

  String _fmt(int v) => format?.call(v) ?? '$v';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return Semantics(
      container: true,
      label: '$label : ${_fmt(value)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: highlight
                ? AppColors.accent.withValues(alpha: 0.45)
                : AppColors.outlineSoft,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: AppSpacing.sm),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: animate ? countDuration : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _fmt(v.round()),
                  maxLines: 1,
                  style: theme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(label, style: theme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Lays KPI tiles in rows of equal height: 4 per row on wide screens,
/// 2 on phones.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 2;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += columns) {
        final cells = <Widget>[];
        for (var c = 0; c < columns; c++) {
          if (c > 0) cells.add(const SizedBox(width: AppSpacing.sm));
          final index = i + c;
          cells.add(Expanded(
              child: index < children.length
                  ? children[index]
                  : const SizedBox.shrink()));
        }
        if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
        rows.add(IntrinsicHeight(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });
  }
}
