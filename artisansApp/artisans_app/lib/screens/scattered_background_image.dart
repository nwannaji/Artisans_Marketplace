import 'dart:math';
import 'package:flutter/material.dart';

class ScatteredBackground extends StatelessWidget {
  final int imageCount;
  final Widget child; // Accept any widget

  const ScatteredBackground({
    super.key,
    this.imageCount = 10,
    required this.child, // Correct type and required keyword
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final random = Random();

    // Generate random Positioned images
    List<Widget> scatteredImages = List.generate(imageCount, (index) {
      double top = random.nextDouble() * screenSize.height;
      double left = random.nextDouble() * screenSize.width;

      return Positioned(
        top: top,
        left: left,
        child: Opacity(
          opacity: 0.05,
          child: Image.asset('assets/setting.webp', width: 60, height: 60),
        ),
      );
    });

    return Stack(
      children: [
        // Background images
        ...scatteredImages,

        // Foreground content (TextFields, etc.)
        Positioned.fill(child: child),
      ],
    );
  }
}
