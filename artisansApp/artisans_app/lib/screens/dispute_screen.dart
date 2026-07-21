// lib/screens/dispute_screen.dart
import 'package:artisans_app/models/dispute.dart';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/services/dispute_api_service.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class DisputeScreen extends StatefulWidget {
  final int? jobId;
  const DisputeScreen({super.key, this.jobId});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> with SingleTickerProviderStateMixin {
  final DisputeApiService _disputeService = DisputeApiService();
  final BookingApiService _bookingService = BookingApiService();
  late TabController _tabController;

  List<Dispute> _disputes = [];
  List<Job> _eligibleJobs = [];
  bool _isLoading = true;
  String? _error;

  // Form state
  Job? _selectedJob;
  DisputeReason _selectedReason = DisputeReason.poorService;
  final _detailsController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final disputes = await _disputeService.listDisputes();
      final allJobs = await _bookingService.listJobs();
      // Only show jobs that are in-progress, awaiting review, completed, or disputed for filing disputes
      final eligible = allJobs.where((j) =>
        j.status == JobStatus.inProgress ||
        j.status == JobStatus.awaitingReview ||
        j.status == JobStatus.completed ||
        j.status == JobStatus.disputed
      ).toList();
      if (mounted) {
        setState(() {
          _disputes = disputes;
          _eligibleJobs = eligible;
          _isLoading = false;
          _error = null;
        });
        // Pre-select job if jobId was provided
        if (widget.jobId != null) {
          final job = eligible.where((j) => j.id == widget.jobId).firstOrNull;
          if (job != null) {
            _selectedJob = job;
            _tabController.animateTo(1); // Switch to File Dispute tab
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _submitDispute() async {
    if (_selectedJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a job'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_detailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide details'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _disputeService.createDispute(
        jobId: _selectedJob!.id,
        reason: _selectedReason,
        details: _detailsController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispute filed successfully'), backgroundColor: Colors.green),
        );
        _detailsController.clear();
        _selectedJob = null;
        _tabController.animateTo(0);
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to file dispute: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _reasonLabel(DisputeReason reason) {
    switch (reason) {
      case DisputeReason.poorService: return 'Poor Service';
      case DisputeReason.notCompleted: return 'Not Completed';
      case DisputeReason.overCharging: return 'Over Charging';
      case DisputeReason.other: return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disputes'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Disputes'),
            Tab(text: 'File Dispute'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // My Disputes tab
                    RefreshIndicator(
                      onRefresh: _loadData,
                      child: _disputes.isEmpty
                          ? const Center(child: Text('No disputes filed yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _disputes.length,
                              itemBuilder: (context, index) => _buildDisputeCard(_disputes[index]),
                            ),
                    ),
                    // File Dispute tab
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Select Job', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Job>(
                            value: _selectedJob,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.work),
                              isDense: true,
                            ),
                            isExpanded: true,
                            items: _eligibleJobs.map((job) => DropdownMenuItem(
                              value: job,
                              child: Text(
                                '#${job.id} - ${job.description}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )).toList(),
                            onChanged: (job) => setState(() => _selectedJob = job),
                          ),
                          const SizedBox(height: 16),
                          const Text('Reason', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<DisputeReason>(
                            value: _selectedReason,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.report_problem),
                            ),
                            items: DisputeReason.values.map((reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(_reasonLabel(reason)),
                            )).toList(),
                            onChanged: (reason) => setState(() => _selectedReason = reason!),
                          ),
                          const SizedBox(height: 16),
                          const Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _detailsController,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              hintText: 'Describe the issue in detail...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submitDispute,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: _isSubmitting
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('File Dispute', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDisputeCard(Dispute dispute) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Job #${dispute.jobId}', style: const TextStyle(fontWeight: FontWeight.w600)),
                StatusBadge.outlined(
                  label: AppColors.disputeStatusLabel(dispute.status),
                  color: AppColors.disputeStatusColor(dispute.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                StatusBadge.outlined(
                  label: _reasonLabel(dispute.reason),
                  color: AppColors.disputeReasonColor(dispute.reason),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(dispute.details, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (dispute.resolution != null) ...[
              const Divider(height: 16),
              Text('Resolution: ${dispute.resolution!}', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green)),
            ],
          ],
        ),
      ),
    );
  }
}