// lib/screens/artisan_list_screen.dart
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/theme/app_spacing.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:artisans_app/widgets/profile_avatar.dart';
import 'package:artisans_app/widgets/empty_state.dart';
import 'package:artisans_app/widgets/rating_selector.dart';
import 'package:artisans_app/viewmodels/base_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/artisan_list_view_model.dart';

class ArtisanListScreen extends StatelessWidget {
  const ArtisanListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ArtisanListViewModel()..fetchArtisans(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Artisans')),
        body: Consumer<ArtisanListViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.state == ViewState.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (viewModel.state == ViewState.error) {
              return ErrorState(
                message: viewModel.errorMessage ?? 'Failed to load artisans',
                onRetry: () => viewModel.fetchArtisans(),
              );
            }
            if (viewModel.artisans.isEmpty) {
              return const EmptyState(
                icon: Icons.search_off,
                title: 'No artisans found',
                subtitle: 'Try adjusting your search or check back later.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => viewModel.fetchArtisans(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                itemCount: viewModel.artisans.length,
                itemBuilder: (context, index) {
                  final artisan = viewModel.artisans[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProfileScreen(artisanId: artisan.id)),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            // Avatar with availability indicator
                            Stack(
                              children: [
                                ProfileAvatar(
                                  imageUrl: artisan.profilePicture,
                                  name: artisan.fullName,
                                  radius: 24,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                  foregroundColor: AppColors.primary,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppColors.availabilityColor(artisan.isAvailable),
                                      shape: BoxShape.circle,
                                      border: Border.fromBorderSide(
                                        const BorderSide(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: AppSpacing.md),
                            // Name, profession, and rating
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    artisan.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    artisan.profession ?? 'Artisan',
                                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 4),
                                  StarRatingDisplay(
                                    rating: artisan.rating,
                                    reviewCount: artisan.reviewCount,
                                    starSize: 14,
                                  ),
                                ],
                              ),
                            ),
                            // Availability badge
                            StatusBadge.outlined(
                              label: _availabilityLabel(artisan.isAvailable),
                              color: AppColors.availabilityColor(artisan.isAvailable),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _availabilityLabel(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE': return 'Available';
      case 'ENGAGED': return 'Engaged';
      case 'BUSY': return 'Busy';
      case 'OFFLINE': return 'Offline';
      default: return status;
    }
  }
}