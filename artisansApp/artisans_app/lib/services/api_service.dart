import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/artisan.dart';
import '../models/job.dart';

class ApiService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Artisan>> searchArtisans({
    String? profession,
    String? location,
    double? maxDistance,
    double? minRating,
    double? maxHourlyRate,
    double? userLat,
    double? userLng,
  }) async {
    try {
      Query query = _firestore
          .collection('artisans')
          .where('isVerified', isEqualTo: true);

      if (profession != null) {
        query = query.where('profession', isEqualTo: profession);
      }

      if (minRating != null) {
        query = query.where('rating', isGreaterThanOrEqualTo: minRating);
      }

      if (maxHourlyRate != null) {
        query = query.where('hourlyRate', isLessThanOrEqualTo: maxHourlyRate);
      }

      final snapshot = await query.get();

      List<Artisan> artisans =
          snapshot.docs
              .map((doc) => Artisan.fromMap(doc.data() as Map<String, dynamic>))
              .toList();

      // Filter by distance if location parameters are provided
      if (userLat != null && userLng != null && maxDistance != null) {
        artisans =
            artisans.where((artisan) {
              final distance = Geolocator.distanceBetween(
                userLat,
                userLng,
                artisan.latitude,
                artisan.longitude,
              );
              return distance <= maxDistance * 1000; // Convert km to meters
            }).toList();
      }

      return artisans;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching artisans: $e');
      }
      return [];
    }
  }

  Future<List<Job>> getJobsForUser(
    String userId, {
    bool isArtisan = false,
  }) async {
    try {
      final field = isArtisan ? 'artisanId' : 'customerId';
      final snapshot =
          await _firestore
              .collection('jobs')
              .where(field, isEqualTo: userId)
              .orderBy('scheduledTime', descending: true)
              .get();

      return snapshot.docs.map((doc) => Job.fromMap(doc.data())).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting jobs: $e');
      }
      return [];
    }
  }

  Future<void> createJob({
    required String customerId,
    required String artisanId,
    required String description,
    required DateTime scheduledTime,
    required double agreedPrice,
    required String location,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final docRef = _firestore.collection('jobs').doc();
      await docRef.set({
        'id': docRef.id,
        'customerId': customerId,
        'artisanId': artisanId,
        'description': description,
        'scheduledTime': scheduledTime.toIso8601String(),
        'agreedPrice': agreedPrice,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'status': JobStatus.scheduled,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error creating job: $e');
      }
      rethrow;
    }
  }

  Future<void> updateJobStatus(String jobId, JobStatus status) async {
    try {
      await _firestore.collection('jobs').doc(jobId).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error updating job status: $e');
      }
      rethrow;
    }
  }

  Future<void> rateJob(String jobId, double rating, String review) async {
    try {
      await _firestore.collection('jobs').doc(jobId).update({
        'rating': rating,
        'review': review,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update artisan's average rating
      final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
      final job = Job.fromMap(jobDoc.data() as Map<String, dynamic>);

      final artisanRef = _firestore.collection('artisans').doc(job.artisanId);
      final artisanDoc = await artisanRef.get();
      final artisan = Artisan.fromMap(
        artisanDoc.data() as Map<String, dynamic>,
      );

      // Calculate new average rating
      final newJobsCompleted = artisan.jobsCompleted + 1;
      final newRating =
          ((artisan.rating * artisan.jobsCompleted) + rating) /
          newJobsCompleted;

      await artisanRef.update({
        'rating': newRating,
        'jobsCompleted': newJobsCompleted,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error rating job: $e');
      }
      rethrow;
    }
  }
}
