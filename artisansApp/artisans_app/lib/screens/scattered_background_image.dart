import 'dart:math';
import 'package:flutter/material.dart';

class ScatteredBackground extends StatelessWidget {
  final int imageCount;
  final Widget child;

  // Seeded random to prevent position flickering on rebuilds
  static final Random _random = Random(42);

  const ScatteredBackground({
    super.key,
    this.imageCount = 10,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Generate positioned images using seeded random for stable positions
    List<Widget> scatteredImages = List.generate(imageCount, (index) {
      double top = _random.nextDouble() * screenSize.height;
      double left = _random.nextDouble() * screenSize.width;

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
        ...scatteredImages,
        Positioned.fill(child: child),
      ],
    );
  }
}
