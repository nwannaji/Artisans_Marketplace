// lib/services/dispute_api_service.dart

import '../models/dispute.dart';
import 'api_client.dart';

class DisputeApiService {
  final ApiClient _apiClient = ApiClient();

  /// List disputes (scoped by role: admin sees all, others see their own)
  Future<List<Dispute>> listDisputes() async {
    final result = await _apiClient.getList('/api/disputes/disputes/');
    return result.map((json) => Dispute.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Create a new dispute
  Future<Dispute> createDispute({
    required int jobId,
    required DisputeReason reason,
    required String details,
  }) async {
    final dispute = Dispute(
      id: 0,
      jobId: jobId,
      reason: reason,
      details: details,
    );
    final result = await _apiClient.post('/api/disputes/disputes/', body: dispute.toCreateJson());
    return Dispute.fromJson(result);
  }

  /// Get a single dispute
  Future<Dispute> getDispute(int pk) async {
    final result = await _apiClient.get('/api/disputes/disputes/$pk/');
    return Dispute.fromJson(result);
  }

  /// Resolve a dispute (admin only)
  Future<Dispute> resolveDispute(int pk, {
    required String resolution,
  }) async {
    final body = <String, dynamic>{'resolution': resolution};

    final result = await _apiClient.patch('/api/disputes/disputes/resolve/$pk/', body: body);
    return Dispute.fromJson(result);
  }
}