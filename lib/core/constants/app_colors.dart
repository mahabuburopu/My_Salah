import 'package:flutter/material.dart';

class AppColors {
  // Gold accent — same in both themes
  static const Color gold = Color(0xFFC9A87C);
  static const Color goldLight = Color(0xFFDEC098);
  static const Color goldDark = Color(0xFF9E7A4E);

  // Status Colors
  static const Color onTime = Color(0xFF1B5E3B);
  static const Color onTimeLight = Color(0xFF2E7D52);
  static const Color qaza = Color(0xFFD4A017);
  static const Color missed = Color(0xFFCC3333);
  static const Color upcoming = Color(0xFF9E9E9E);

  // Prayer Icon Colors
  static const Color fajrColor = Color(0xFF6B8CAE);
  static const Color dhuhrColor = Color(0xFFE8B84B);
  static const Color asrColor = Color(0xFF8FAF6B);
  static const Color maghribColor = Color(0xFFE87B4B);
  static const Color ishaColor = Color(0xFF7B6BAE);

  //Static dark values (for widgets that need a constant) 
  static const Color darkBg = Color(0xFF1A1008);
  static const Color darkSurface = Color(0xFF251A0E);
  static const Color darkCard = Color(0xFF2C1F11);
  static const Color darkBorder = Color(0xFF3D2E1A);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA08060);
  static const Color textDark = Color(0xFF1A1008);
  static const Color textMuted = Color(0xFF888888);
  static const Color lightBg = Color(0xFFFAF6F0);
  static const Color lightCard = Color(0xFFFFFFFF);
}

/// AC = App Colors (context-aware, responds to dark/light mode)
class AC {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Main background
  static Color bg(BuildContext context) => isDark(context)
      ? const Color(0xFF1A1008)
      : const Color(0xFFFAF6F0);

  /// Card / container background
  static Color card(BuildContext context) => isDark(context)
      ? const Color(0xFF2C1F11)
      : const Color(0xFFFFFFFF);

  /// Slightly elevated surface
  static Color surface(BuildContext context) => isDark(context)
      ? const Color(0xFF251A0E)
      : const Color(0xFFF5EFE6);

  /// Border / divider color
  static Color border(BuildContext context) => isDark(context)
      ? const Color(0xFF3D2E1A)
      : const Color(0xFFE8DDD0);

  /// Primary text
  static Color text(BuildContext context) => isDark(context)
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF1A1008);

  /// Secondary / muted text
  static Color textSub(BuildContext context) => isDark(context)
      ? const Color(0xFFA08060)
      : const Color(0xFF8B6914);

  /// Gold accent — stays the same in both
  static const Color gold = Color(0xFFC9A87C);
  static const Color goldLight = Color(0xFFDEC098);

  // Status colors
  static const Color onTime = Color(0xFF1B5E3B);
  static const Color onTimeLight = Color(0xFF2E7D52);
  static const Color qaza = Color(0xFFD4A017);
  static const Color missed = Color(0xFFCC3333);

  // Prayer colors
  static const Color fajrColor = Color(0xFF6B8CAE);
  static const Color dhuhrColor = Color(0xFFE8B84B);
  static const Color asrColor = Color(0xFF8FAF6B);
  static const Color maghribColor = Color(0xFFE87B4B);
  static const Color ishaColor = Color(0xFF7B6BAE);
}
