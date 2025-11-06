import 'package:flutter/material.dart';

TextTheme buildTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontFamily: 'Cairo'),
    displayMedium: base.displayMedium?.copyWith(fontFamily: 'Cairo'),
    displaySmall: base.displaySmall?.copyWith(fontFamily: 'Cairo'),
    headlineLarge: base.headlineLarge?.copyWith(fontFamily: 'Cairo'),
    headlineMedium: base.headlineMedium?.copyWith(fontFamily: 'Cairo'),
    headlineSmall: base.headlineSmall?.copyWith(fontFamily: 'Cairo'),
    titleLarge: base.titleLarge?.copyWith(fontFamily: 'Cairo'),
    titleMedium: base.titleMedium?.copyWith(fontFamily: 'Cairo'),
    titleSmall: base.titleSmall?.copyWith(fontFamily: 'Cairo'),
    bodyLarge: base.bodyLarge?.copyWith(fontFamily: 'Cairo'),
    bodyMedium: base.bodyMedium?.copyWith(fontFamily: 'Cairo'),
    bodySmall: base.bodySmall?.copyWith(fontFamily: 'Cairo'),
    labelLarge: base.labelLarge?.copyWith(fontFamily: 'Cairo'),
    labelMedium: base.labelMedium?.copyWith(fontFamily: 'Cairo'),
    labelSmall: base.labelSmall?.copyWith(fontFamily: 'Cairo'),
  );
}
