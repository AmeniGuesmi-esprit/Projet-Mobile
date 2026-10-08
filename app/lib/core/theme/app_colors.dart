import 'package:flutter/material.dart';

/// ProxiLife color palette. Usage rules are enforced by the
/// `proxilife-ui-design` skill — the key constraint is about contrast:
/// never put white text on [accent] or [warning].
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF1B7F5C);
  static const Color primaryDeep = Color(0xFF0F4D38);
  static const Color accent = Color(0xFFFF8A3D);
  static const Color background = Color(0xFFF5F8F6);

  // Text
  static const Color text = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF6B7A75);

  /// Darker variant of [textSecondary] for body-size text (small text at
  /// 0xFF6B7A75 on the background fails the 4.5:1 contrast ratio).
  static const Color textSecondaryStrong = Color(0xFF4F5E58);

  // Surfaces & lines
  static const Color surface = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFDDE5E0);
  static const Color outlineSoft = Color(0xFFE9EFEC);

  // Semantic states
  static const Color success = Color(0xFF2E9E5B);
  static const Color info = Color(0xFF2F80ED);
  static const Color warning = Color(0xFFF2B84B);
  static const Color error = Color(0xFFD64545);

  // Modules (see flutter-ux-patterns: always pair TeleDoc colour with the
  // service label, not used alone, because it is close to [error]).
  static const Color moduleCompte = primary;
  static const Color moduleEcoRoute = Color(0xFF2F80ED);
  static const Color moduleFoodSave = Color(0xFFE07B1F);
  static const Color moduleTeleDoc = Color(0xFFE0525B);
  static const Color moduleCoachProche = Color(0xFF8E5BD9);

  static const LinearGradient balanceCardGradient = LinearGradient(
    colors: [primary, primaryDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
