// lib/theme/app_typography.dart
//
// Semantic typography tokens. Use these instead of hardcoded TextStyle(...)
// to keep the app visually consistent and easy to update.

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  /// Large headline — 22px bold. Used for screen titles, hero numbers.
  static TextStyle headline1(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ) ??
      const TextStyle(fontSize: 22, fontWeight: FontWeight.bold);

  /// Medium headline — 18px semi-bold. Used for section headers, card titles.
  static TextStyle headline2(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ) ??
      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  /// Body text — 16px normal. Used for descriptions, form labels.
  static TextStyle body1(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16) ??
      const TextStyle(fontSize: 16);

  /// Secondary body — 14px normal. Used for subtitles, helper text.
  static TextStyle body2(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14) ??
      const TextStyle(fontSize: 14);

  /// Bold body — 16px w600. Used for emphasis within body text.
  static TextStyle bodyBold(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ) ??
      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  /// Caption — 12px, secondary color. Used for timestamps, metadata.
  static TextStyle caption(BuildContext context) => TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
      );

  /// Label — 11px bold. Used inside badges, chips, status tags.
  static TextStyle label(BuildContext context) => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
      );

  /// Price — 18px bold. Used for monetary values.
  static TextStyle price(BuildContext context) => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      );
}