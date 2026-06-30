// lib/widgets/info_callout.dart
//
// A reusable info/warning/success callout box that replaces the
// duplicated amber Container+BoxDecoration pattern found across screens.

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

enum InfoCalloutType { info, warning, success }

class InfoCallout extends StatelessWidget {
  final String message;
  final IconData icon;
  final InfoCalloutType type;

  const InfoCallout({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.type = InfoCalloutType.info,
  });

  /// Amber info callout — default style for informational notes.
  const InfoCallout.info({
    Key? key,
    required String message,
    IconData icon = Icons.info_outline,
  }) : this(key: key, message: message, icon: icon, type: InfoCalloutType.info);

  /// Orange warning callout — for important warnings or pending statuses.
  const InfoCallout.warning({
    Key? key,
    required String message,
    IconData icon = Icons.warning_amber,
  }) : this(key: key, message: message, icon: icon, type: InfoCalloutType.warning);

  /// Green success callout — for confirmations or positive notes.
  const InfoCallout.success({
    Key? key,
    required String message,
    IconData icon = Icons.check_circle_outline,
  }) : this(key: key, message: message, icon: icon, type: InfoCalloutType.success);

  @override
  Widget build(BuildContext context) {
    final colors = _calloutColors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.iconColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: colors.textColor),
            ),
          ),
        ],
      ),
    );
  }

  _CalloutColors _calloutColors() {
    switch (type) {
      case InfoCalloutType.info:
        return _CalloutColors(
          backgroundColor: Colors.amber.shade50,
          borderColor: Colors.amber.shade200,
          iconColor: Colors.amber.shade700,
          textColor: Colors.amber.shade900,
        );
      case InfoCalloutType.warning:
        return _CalloutColors(
          backgroundColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
          iconColor: Colors.orange.shade700,
          textColor: Colors.orange.shade900,
        );
      case InfoCalloutType.success:
        return _CalloutColors(
          backgroundColor: Colors.green.shade50,
          borderColor: Colors.green.shade200,
          iconColor: Colors.green.shade700,
          textColor: Colors.green.shade900,
        );
    }
  }
}

class _CalloutColors {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;

  const _CalloutColors({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
  });
}