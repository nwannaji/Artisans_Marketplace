import 'package:artisans_app/widgets/rating_stars.dart';
import 'package:flutter/material.dart';

import '../models/artisan.dart';

class ArtisanCard extends StatelessWidget {
  final Artisan artisan;
  final VoidCallback onTap;

  const ArtisanCard({super.key, required this.artisan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(child: Text(artisan.name[0])),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artisan.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(artisan.profession),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  RatingStars(rating: artisan.rating),
                  SizedBox(width: 8),
                  Text('(${artisan.jobsCompleted} jobs)'),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16),
                  SizedBox(width: 4),
                  Text(artisan.location),
                  Spacer(),
                  Text(
                    '\$${artisan.hourlyRate.toStringAsFixed(2)}/hr',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
