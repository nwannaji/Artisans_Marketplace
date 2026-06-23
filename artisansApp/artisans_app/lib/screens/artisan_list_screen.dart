// lib/screens/artisan_list_screen.dart
import 'package:artisans_app/screens/artisan_profile.dart';
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
              return Center(child: Text('Error: ${viewModel.errorMessage}'));
            }
            if (viewModel.artisans.isEmpty) {
              return const Center(child: Text('No artisans found.'));
            }
            return ListView.builder(
              itemCount: viewModel.artisans.length,
              itemBuilder: (context, index) {
                final artisan = viewModel.artisans[index];
                return ListTile(
                  leading: const CircleAvatar(
                    // backgroundImage: NetworkImage(artisan.photoUrl),
                  ),
                  title: Text(artisan.fullName),
                  subtitle: Text(artisan.profession ?? 'N/A'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      Text(artisan.rating.toStringAsFixed(1)),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileScreen(artisanId: artisan.id)),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
