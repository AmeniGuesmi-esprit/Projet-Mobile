import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// CoachProche colours: the module's violet from the specification
/// (`AppColors.moduleCoachProche`) instead of ProxiLife's green.
abstract final class CoachColors {
  /// Brand violet of the specification: tints, icons, chips.
  static const Color brand = AppColors.moduleCoachProche;

  /// Same hue, darker: buttons, links and violet text on white
  /// (white on this shade reaches 6.8:1, WCAG AA).
  static const Color brandDeep = Color(0xFF6D3FB8);

  /// Very light violet background (hero cards, selected tiles).
  static const Color brandSoft = Color(0xFFF3EDFB);

  /// Text on the light violet selected segment / chip.
  static const Color onBrandSoft = Color(0xFF4A2A85);
}

/// The app theme with CoachProche's violet as primary colour. Built from
/// the current theme, so the shared `AppTheme` is not modified.
ThemeData coachTheme(ThemeData base) => base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: CoachColors.brandDeep,
        onPrimary: Colors.white,
        surfaceTint: CoachColors.brand,
        secondary: CoachColors.brandDeep,
        secondaryContainer: CoachColors.brand.withValues(alpha: 0.15),
        onSecondaryContainer: CoachColors.onBrandSoft,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).merge(
          FilledButton.styleFrom(
            backgroundColor: CoachColors.brandDeep,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).merge(
          OutlinedButton.styleFrom(
            foregroundColor: CoachColors.brandDeep,
            side: const BorderSide(color: CoachColors.brandDeep, width: 1.4),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).merge(
          TextButton.styleFrom(foregroundColor: CoachColors.brandDeep),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide:
              const BorderSide(color: CoachColors.brandDeep, width: 1.6),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: CoachColors.brand.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? CoachColors.brandDeep
                : AppColors.textSecondary,
          ),
        ),
      ),
      progressIndicatorTheme:
          base.progressIndicatorTheme.copyWith(color: CoachColors.brandDeep),
    );

/// Applies [coachTheme] to a CoachProche page.
class CoachThemed extends StatelessWidget {
  const CoachThemed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: coachTheme(Theme.of(context)),
        // Text fields read their cursor colour from the selection style that
        // MaterialApp sets above any Theme: override it too.
        child: DefaultSelectionStyle(
          cursorColor: CoachColors.brandDeep,
          selectionColor: CoachColors.brand.withValues(alpha: 0.30),
          child: child,
        ),
      );
}

/// Route used for every CoachProche page, so that each pushed screen (and
/// the dialogs it opens) gets the violet colours.
class CoachPageRoute<T> extends MaterialPageRoute<T> {
  CoachPageRoute({required WidgetBuilder builder})
      : super(builder: (context) => CoachThemed(child: builder(context)));
}

/// Pushes [page] with the CoachProche theme.
Future<T?> pushCoach<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(CoachPageRoute<T>(builder: (_) => page));
