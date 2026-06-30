// lib/widgets/drag_handle.dart
//
// A reusable bottom-sheet drag handle that replaces the duplicated
// Container(width:40, height:4, ...) pattern found across 6 screens.

import 'package:flutter/material.dart';

class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}