import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ArtisanMapScreen extends StatefulWidget {
  final Artisan artisan;
  final LatLng? userLocation;

  const ArtisanMapScreen({super.key, required this.artisan, this.userLocation});

  @override
  State<ArtisanMapScreen> createState() => _ArtisanMapScreenState();
}

class _ArtisanMapScreenState extends State<ArtisanMapScreen> {
  @override
  Widget build(BuildContext context) {
    final artisan = widget.artisan;

    // If artisan has no location, show a message instead of map
    if (artisan.latitude == null || artisan.longitude == null) {
      return Scaffold(
        appBar: AppBar(title: Text(artisan.fullName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '${artisan.fullName} has not shared their location.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final artisanPosition = LatLng(artisan.latitude!, artisan.longitude!);

    // Build markers
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('artisan'),
        position: artisanPosition,
        infoWindow: InfoWindow(
          title: artisan.fullName,
          snippet: '${artisan.profession ?? "Artisan"} • ★ ${artisan.rating.toStringAsFixed(1)}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    };

    // Add user location marker if available
    if (widget.userLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('user'),
        position: widget.userLocation!,
        infoWindow: const InfoWindow(title: 'You are here'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(artisan.fullName),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: artisanPosition,
          zoom: 14.0,
        ),
        markers: markers,
        onMapCreated: (controller) {
          // If we have both user and artisan positions, zoom to show both
          if (widget.userLocation != null) {
            final bounds = _calculateBounds(widget.userLocation!, artisanPosition);
            controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
          }
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        compassEnabled: true,
      ),
      // Floating info card at the bottom
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, -2)),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: artisan.profilePicture != null
                    ? NetworkImage(artisan.profilePicture!)
                    : null,
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: artisan.profilePicture == null
                    ? Text(
                        artisan.fullName.substring(0, 1).toUpperCase(),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(artisan.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                        if (artisan.isVerified)
                          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: AppColors.verifiedBlue)),
                      ],
                    ),
                    if (artisan.profession != null)
                      Text(artisan.profession!, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        Text(' ${artisan.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                        if (artisan.reviewCount > 0)
                          Text(' (${artisan.reviewCount})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProfileScreen(artisanId: artisan.id, artisanData: artisan)),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LatLngBounds _calculateBounds(LatLng p1, LatLng p2) {
    final southWest = LatLng(
      p1.latitude < p2.latitude ? p1.latitude : p2.latitude,
      p1.longitude < p2.longitude ? p1.longitude : p2.longitude,
    );
    final northEast = LatLng(
      p1.latitude > p2.latitude ? p1.latitude : p2.latitude,
      p1.longitude > p2.longitude ? p1.longitude : p2.longitude,
    );
    return LatLngBounds(southwest: southWest, northeast: northEast);
  }
}