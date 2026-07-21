// lib/theme/app_colors.dart
//
// Single source of truth for all color constants and semantic color mappings.
// Replaces the scattered _statusColor / _availabilityColor / _transactionColor
// methods duplicated across 6+ screens.

import 'package:flutter/material.dart';
import '../models/job.dart';
import '../models/dispute.dart';

class AppColors {
  AppColors._();

  // ── Primary palette (CHOP LIFE design system) ────────────────────────
  static const Color primary = Color(0xFF1E3A8A);       // Deep Trust Blue
  static const Color primaryDark = Color(0xFF1E3A5F);    // Darker Blue
  static const Color primaryLight = Color(0xFFDBEAFE);  // Blue 100
  static const Color accent = Color(0xFFD97706);         // Abuja Gold / Amber
  static const Color background = Color(0xFFF8FAFC);     // Clean Slate
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);   // Slate 900
  static const Color textSecondary = Color(0xFF64748B);  // Slate 500
  static const Color verifiedBlue = Color(0xFF0284C7);   // Trust verification badge

  // ── Gradients ────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1E3A8A), Color(0xFF1E3A5F)], // Deep Trust Blue gradient
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Job status colors ────────────────────────────────────────────────
  /// Canonical color for each [JobStatus].
  /// This is the single source of truth — all screens should use this
  /// instead of their own _statusColor() methods.
  static Color jobStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return Colors.orange;
      case JobStatus.adminApproved:
        return Colors.lightBlue;
      case JobStatus.accepted:
        return Colors.blue;
      case JobStatus.inProgress:
        return Colors.orange;
      case JobStatus.awaitingReview:
        return Colors.purple;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.cancelled:
        return Colors.red;
      case JobStatus.disputed:
        return Colors.deepOrange;
      case JobStatus.rejected:
        return Colors.grey;
    }
  }

  // ── Availability colors ─────────────────────────────────────────────
  /// Color for artisan availability strings ('AVAILABLE', 'ENGAGED', etc.)
  static Color availabilityColor(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return Colors.green;
      case 'ENGAGED':
        return Colors.orange;
      case 'BUSY':
        return Colors.red;
      case 'OFFLINE':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  // ── Dispute status / reason colors ───────────────────────────────────
  static Color disputeStatusColor(DisputeStatus status) {
    switch (status) {
      case DisputeStatus.open:
        return Colors.red;
      case DisputeStatus.inReview:
        return Colors.orange;
      case DisputeStatus.resolved:
        return Colors.green;
      case DisputeStatus.closed:
        return Colors.grey;
    }
  }

  static String disputeStatusLabel(DisputeStatus status) {
    switch (status) {
      case DisputeStatus.open:
        return 'Open';
      case DisputeStatus.inReview:
        return 'In Review';
      case DisputeStatus.resolved:
        return 'Resolved';
      case DisputeStatus.closed:
        return 'Closed';
    }
  }

  static Color disputeReasonColor(DisputeReason reason) {
    switch (reason) {
      case DisputeReason.poorService:
        return Colors.red;
      case DisputeReason.notCompleted:
        return Colors.orange;
      case DisputeReason.overCharging:
        return Colors.deepOrange;
      case DisputeReason.other:
        return Colors.grey;
    }
  }
}