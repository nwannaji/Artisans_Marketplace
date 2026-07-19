// lib/screens/home_screen.dart
//
// Landing home screen showing the two personas (Customer & Artisan).
// Tapping either persona navigates to the corresponding dashboard.

import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                // App title
                Text(
                  'FIXIT APP',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Connecting You with Trusted Professionals',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Customer persona
                _PersonaCard(
                  imagePath: 'assets/images/Persona_Image.png',
                  label: 'I Need a Service',
                  subtitle: 'Find & hire trusted artisans near you',
                  color: AppColors.primary,
                  onTap: () => Navigator.pushReplacementNamed(context, '/user_home'),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Artisan persona
                _PersonaCard(
                  imagePath: 'assets/images/artisan_persona.png',
                  label: 'I Am an Artisan',
                  subtitle: 'Offer your skills & grow your business',
                  color: AppColors.accent,
                  onTap: () => Navigator.pushReplacementNamed(context, '/artisan_dashboard'),
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular avatar card with label, subtitle, and tap action.
class _PersonaCard extends StatelessWidget {
  final String imagePath;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PersonaCard({
    required this.imagePath,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 80,
              backgroundImage: AssetImage(imagePath),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}