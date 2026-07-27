// Unit tests for Dispute model
import 'package:flutter_test/flutter_test.dart';
import 'package:artisans_app/models/dispute.dart';

void main() {
  group('Dispute', () {
    test('fromJson creates dispute from API response', () {
      final json = {
        'id': 1,
        'job_id': 10,
        'reason': 'poor_service',
        'details': 'The artisan did not complete the work as agreed.',
        'status': 'open',
        'resolution': null,
        'resolved_by_id': null,
        'created_at': '2025-01-15T10:30:00Z',
        'updated_at': '2025-01-15T10:30:00Z',
      };

      final dispute = Dispute.fromJson(json);

      expect(dispute.id, 1);
      expect(dispute.jobId, 10);
      expect(dispute.reason, DisputeReason.poorService);
      expect(dispute.status, DisputeStatus.open);
      expect(dispute.resolution, isNull);
    });

    test('fromJson handles alternative job field name', () {
      final json = {
        'id': 2,
        'job': 20,
        'reason': 'not_completed',
        'details': 'Work was not completed.',
        'status': 'in_review',
        'created_at': '2025-02-01T00:00:00Z',
      };

      final dispute = Dispute.fromJson(json);

      expect(dispute.jobId, 20);
      expect(dispute.reason, DisputeReason.notCompleted);
      expect(dispute.status, DisputeStatus.inReview);
    });

    test('fromJson handles all status values', () {
      final statusMap = {
        'open': DisputeStatus.open,
        'in_review': DisputeStatus.inReview,
        'resolved': DisputeStatus.resolved,
        'closed': DisputeStatus.closed,
      };

      statusMap.forEach((apiStatus, expectedStatus) {
        final json = {
          'id': 1,
          'job_id': 1,
          'reason': 'other',
          'details': 'Test',
          'status': apiStatus,
        };

        final dispute = Dispute.fromJson(json);
        expect(dispute.status, expectedStatus);
      });
    });

    test('fromJson handles all reason values', () {
      final reasonMap = {
        'poor_service': DisputeReason.poorService,
        'not_completed': DisputeReason.notCompleted,
        'over_charging': DisputeReason.overCharging,
        'other': DisputeReason.other,
      };

      reasonMap.forEach((apiReason, expectedReason) {
        final json = {
          'id': 1,
          'job_id': 1,
          'reason': apiReason,
          'details': 'Test',
          'status': 'open',
        };

        final dispute = Dispute.fromJson(json);
        expect(dispute.reason, expectedReason);
      });
    });

    test('toCreateJson produces correct API format', () {
      final dispute = Dispute(
        id: 1,
        jobId: 5,
        reason: DisputeReason.poorService,
        details: 'Bad work',
      );

      final json = dispute.toCreateJson();

      expect(json['job_id'], 5);
      expect(json['reason'], 'poor_service');
      expect(json['details'], 'Bad work');
    });

    test('Equatable works for Dispute comparison', () {
      final d1 = Dispute(id: 1, jobId: 1, reason: DisputeReason.other, details: 'a');
      final d2 = Dispute(id: 1, jobId: 1, reason: DisputeReason.other, details: 'a');
      final d3 = Dispute(id: 2, jobId: 1, reason: DisputeReason.other, details: 'a');

      expect(d1 == d2, true);
      expect(d1 == d3, false);
    });
  });
}