// lib/widgets/status_badge.dart
//
// A reusable status badge widget that replaces the duplicated
// Container+BoxDecoration pattern found across 15+ screen locations.
// Updated to CHOP LIFE pill-badge style with rounded corners.

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;
  final double borderRadius;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 11,
    this.borderRadius = AppRadius.pillBadge,
  });

  /// Outlined variant: tinted background + border, colored text.
  /// Used for status tags on cards (job status, availability, etc.)
  factory StatusBadge.outlined({
    Key? key,
    required String label,
    required Color color,
    double fontSize = 11,
  }) =>
      StatusBadge(
        key: key,
        label: label,
        color: color,
        fontSize: fontSize,
        borderRadius: AppRadius.pillBadge,
      );

  /// Filled variant: solid background, white text.
  /// Used for prominent badges on cards.
  factory StatusBadge.filled({
    Key? key,
    required String label,
    required Color color,
    double fontSize = 11,
  }) =>
      StatusBadge(
        key: key,
        label: label,
        color: color,
        fontSize: fontSize,
        borderRadius: AppRadius.pillBadge,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}