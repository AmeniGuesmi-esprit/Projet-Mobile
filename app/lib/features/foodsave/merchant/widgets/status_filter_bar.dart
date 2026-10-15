import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// One filter option. A null [value] means "all".
class FilterOption<T> {
  const FilterOption(this.value, this.label);

  final T? value;
  final String label;
}

/// Horizontally scrolling single-choice chips with optional counts
/// ("Disponibles · 3"), in the FoodSave tint.
class StatusFilterBar<T> extends StatelessWidget {
  const StatusFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.counts,
  });

  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;

  /// Count per option value (null key = all). Hidden when null.
  final Map<T?, int>? counts;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      child: Row(
        children: [
          for (final (i, option) in options.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            _chip(option),
          ],
        ],
      ),
    );
  }

  Widget _chip(FilterOption<T> option) {
    final isSelected = option.value == selected;
    final count = counts?[option.value] ?? (counts == null ? null : 0);
    final label = count == null ? option.label : '${option.label} · $count';
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => onSelected(option.value),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      selectedColor: AppColors.moduleFoodSaveSoft,
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: isSelected ? AppColors.moduleFoodSave : AppColors.outline,
      ),
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppColors.moduleFoodSaveDeep : AppColors.text,
      ),
      shape: const StadiumBorder(),
    );
  }
}
