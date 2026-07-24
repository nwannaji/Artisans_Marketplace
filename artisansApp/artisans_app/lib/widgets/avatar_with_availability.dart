// lib/widgets/avatar_with_availability.dart
//
// A CircleAvatar with an availability indicator dot.
// Uses ProfileAvatar internally so broken image URLs (404) show
// the initial letter instead of crashing.

import 'package:flutter/material.dart';
import 'package:artisans_app/widgets/profile_avatar.dart';
import '../theme/app_colors.dart';

class AvatarWithAvailability extends StatelessWidget {
  final String? imageUrl;
  final String fallbackInitial;
  final String availabilityStatus; // 'AVAILABLE', 'ENGAGED', 'BUSY', 'OFFLINE'
  final double radius;
  final VoidCallback? onTap;

  const AvatarWithAvailability({
    super.key,
    this.imageUrl,
    this.fallbackInitial = '?',
    this.availabilityStatus = 'OFFLINE',
    this.radius = 28,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = AppColors.availabilityColor(availabilityStatus);
    final dotSize = radius * 0.35;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ProfileAvatar(
            imageUrl: imageUrl,
            name: fallbackInitial,
            radius: radius,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            foregroundColor: AppColors.primary,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize * 2,
              height: dotSize * 2,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}