import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// TeleDoc Express colours: the module's red from the specification
/// instead of ProxiLife's green (CONCEPTION.md, D44).
abstract final class TeledocColors {
  /// Brand red of the specification (= `AppColors.moduleTeleDoc`): pins,
  /// tints, chips.
  static const Color brand = AppColors.moduleTeleDoc;

  /// Same hue, darker: buttons and red text. White on [brand] is only
  /// 3.8:1; this shade reaches 5.5:1 (WCAG AA, checked by the tests).
  static const Color brandDeep = Color(0xFFC0343E);
}

/// The app theme with TeleDoc's red as primary colour. Built from the
/// current theme, so the shared `AppTheme` is not modified.
ThemeData teledocTheme(ThemeData base) => base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    primary: TeledocColors.brandDeep,
    onPrimary: Colors.white,
    secondary: TeledocColors.brandDeep,
    secondaryContainer: TeledocColors.brand.withValues(alpha: 0.15),
    // Text on the pink selected segment: darker still for 4.5:1.
    onSecondaryContainer: const Color(0xFF8E1F28),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: TeledocColors.brandDeep,
      foregroundColor: Colors.white,
    ).merge(base.filledButtonTheme.style),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: TeledocColors.brandDeep,
      side: const BorderSide(color: TeledocColors.brandDeep, width: 1.4),
    ).merge(base.outlinedButtonTheme.style),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: TeledocColors.brandDeep)
        .merge(base.textButtonTheme.style),
  ),
  inputDecorationTheme: base.inputDecorationTheme.copyWith(
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: TeledocColors.brandDeep, width: 1.6),
    ),
  ),
  progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
    color: TeledocColors.brandDeep,
  ),
);

/// Applies [teledocTheme] to a TeleDoc page.
class TeledocThemed extends StatelessWidget {
  const TeledocThemed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: teledocTheme(Theme.of(context)), child: child);
}

/// Route used for every TeleDoc page, so that each pushed screen (and the
/// dialogs it opens) gets the TeleDoc colours.
class TeledocPageRoute<T> extends MaterialPageRoute<T> {
  TeledocPageRoute({required WidgetBuilder builder})
    : super(builder: (context) => TeledocThemed(child: builder(context)));
}
