import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF19183B); // #19183B
  static const Color secondary = Color(0xFF708993); // #708993
  static const Color tertiary = Color(0xFFA1C2BD); // #A1C2BD
  static const Color surface = Color(0xFFE7F2EF); // #E7F2EF

  static const Color onPrimary = Colors.white;
  static const Color onSurface = Color(0xFF121212);

  static ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: primary,
    onPrimary: onPrimary,
    secondary: secondary,
    tertiary: tertiary,
    surface: surface,
    onSurface: onSurface,
  );

  static ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: tertiary, // يبرز على الخلفيات الداكنة
    secondary: secondary,
    tertiary: primary,
  );
}
