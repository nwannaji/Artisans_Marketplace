// lib/services/booking_api_service.dart

import '../models/job.dart';
import 'api_client.dart';

class BookingApiService {
  final ApiClient _apiClient = ApiClient();

  /// List jobs (scoped by role server-side)
  Future<List<Job>> listJobs({String? status, int? artisan, int? customer}) async {
    final queryParams = <String, dynamic>{};
    if (status != null) queryParams['status'] = status;
    if (artisan != null) queryParams['artisan'] = artisan.toString();
    if (customer != null) queryParams['customer'] = customer.toString();

    final result = await _apiClient.getList('/api/bookings/', queryParams: queryParams.isEmpty ? null : queryParams);
    return result.map((json) => Job.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Create a new job (customer only)
  Future<Job> createJob(Map<String, dynamic> data) async {
    final result = await _apiClient.post('/api/bookings/', body: data);
    return Job.fromJson(result);
  }

  /// Get a single job
  Future<Job> getJob(int pk) async {
    final result = await _apiClient.get('/api/bookings/$pk/');
    return Job.fromJson(result);
  }

  /// Update a job
  Future<Job> updateJob(int pk, Map<String, dynamic> data) async {
    final result = await _apiClient.patch('/api/bookings/$pk/', body: data);
    return Job.fromJson(result);
  }

  /// Update job status (IN_PROGRESS, COMPLETED, CANCELLED, DISPUTED)
  Future<Map<String, dynamic>> updateJobStatus(int pk, String status) async {
    return await _apiClient.patch('/api/bookings/$pk/status/', body: {'status': status});
  }

  /// Admin approve a PENDING job
  Future<Job> approveJob(int pk) async {
    final result = await _apiClient.patch('/api/bookings/$pk/approve/');
    return Job.fromJson(result);
  }

  /// Admin reject a PENDING job
  Future<Job> rejectJob(int pk) async {
    final result = await _apiClient.patch('/api/bookings/$pk/reject/');
    return Job.fromJson(result);
  }

  /// Artisan accept an ADMIN_APPROVED job
  Future<Job> acceptJob(int pk) async {
    final result = await _apiClient.patch('/api/bookings/$pk/accept/');
    return Job.fromJson(result);
  }

  /// Delete a job
  Future<void> deleteJob(int pk) async {
    await _apiClient.delete('/api/bookings/$pk/');
  }

  /// Create a job pre-assigned to a specific artisan (quick-book)
  Future<Job> createJobWithArtisan(Map<String, dynamic> data, int artisanId) async {
    final body = {
      ...data,
      'artisan_id': artisanId,
    };
    final result = await _apiClient.post('/api/bookings/create-with-artisan/', body: body);
    final jobData = result['job'] ?? result;
    return Job.fromJson(jobData as Map<String, dynamic>);
  }

  /// Rate and review a completed job
  Future<Map<String, dynamic>> rateJob(int jobId, double rating, {String? review}) async {
    final body = <String, dynamic>{
      'rating': rating,
    };
    if (review != null && review.trim().isNotEmpty) {
      body['review'] = review.trim();
    }
    return await _apiClient.post('/api/bookings/$jobId/rate/', body: body);
  }
}