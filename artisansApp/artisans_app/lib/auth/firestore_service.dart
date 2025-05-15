import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/artisan.dart';
import '../models/job.dart';
import 'package:logger/logger.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final logger = Logger();
  Future<void> addArtisan(Artisan artisan) async {
    try {
      await _firestore.collection('artisans').doc(artisan.id).set({
        'firstName': artisan.firstName,
        'lastName': artisan.lastName,
        'profilePicture': artisan.profilePicture,
        'expertise': artisan.expertise,
        'location': artisan.location,
        'landmark': artisan.landmark,
        'accountNumber': artisan.accountNumber,
        'bankName': artisan.bankName,
        'ratings': artisan.ratings,
        'status': artisan.status,
      });
    } catch (e) {
      logger.e(e.toString());
    }
  }

  Future<List<Artisan>> getArtisans() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('artisans').get();
      return snapshot.docs
          .map(
            (doc) => Artisan(
              id: doc.id,
              firstName: doc['firstName'],
              lastName: doc['lastname'],
              profilePicture: doc['profilePicture'],
              expertise: doc['expertise'],
              location: doc['location'],
              landmark: doc['landmark'],
              accountNumber: doc['accountName'],
              bankName: doc['bankName'],
              ratings: doc['ratings'],
              status: doc['status'],
            ),
          )
          .toList();
    } catch (e) {
      logger.e(e.toString());
      return [];
    }
  }

  Future<void> addJob(Job job) async {
    try {
      await _firestore.collection('jobs').doc(job.id).set({
        'customerId': job.customerId,
        'artisanId': job.artisanId,
        'jobType': job.jobType,
        'location': job.location,
        'estimatedCost': job.estimatedCost,
        'description': job.description,
        'status': job.status,
      });
    } catch (e) {
      logger.d(e.toString());
    }
  }
}
