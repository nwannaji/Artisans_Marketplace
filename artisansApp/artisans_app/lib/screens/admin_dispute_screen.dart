// lib/screens/admin_dispute_screen.dart
import 'package:artisans_app/models/dispute.dart';
import 'package:artisans_app/widgets/scattered_background_image.dart';
import 'package:artisans_app/services/dispute_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class AdminDisputeScreen extends StatefulWidget {
  const AdminDisputeScreen({super.key});

  @override
  State<AdminDisputeScreen> createState() => _AdminDisputeScreenState();
}

class _AdminDisputeScreenState extends State<AdminDisputeScreen> {
  final DisputeApiService _disputeService = DisputeApiService();
  List<Dispute> _disputes = [];
  bool _isLoading = true;
  String? _error;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadDisputes();
  }

  Future<void> _loadDisputes() async {
    setState(() => _isLoading = true);
    try {
      final disputes = await _disputeService.listDisputes();
      if (mounted) {
        setState(() {
          _disputes = disputes;
          _isLoading = false;
          _error = null;
        });
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

  List<Dispute> get _filteredDisputes {
    if (_filterStatus == 'all') return _disputes;
    return _disputes.where((d) => d.status.name.toLowerCase() == _filterStatus).toList();
  }

  Future<void> _resolveDispute(Dispute dispute) async {
    final resolutionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Dispute'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Job #${dispute.jobId}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Reason: ${_reasonLabel(dispute.reason)}'),
              Text('Details: ${dispute.details}'),
              const SizedBox(height: 16),
              TextField(
                controller: resolutionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resolution *',
                  hintText: 'Describe the resolution...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resolve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final resolution = resolutionController.text.trim();
    if (resolution.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resolution details are required'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await _disputeService.resolveDispute(
        dispute.id,
        resolution: resolution,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispute resolved successfully'), backgroundColor: Colors.green),
        );
        _loadDisputes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
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
    final filtered = _filteredDisputes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispute Management'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDisputes),
        ],
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: Column(
          children: [
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  _buildFilterChip('open', 'Open'),
                  _buildFilterChip('in_review', 'In Review'),
                  _buildFilterChip('resolved', 'Resolved'),
                  _buildFilterChip('closed', 'Closed'),
                ],
              ),
            ),
            // Dispute list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Error: $_error'),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _loadDisputes, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? const Center(child: Text('No disputes found.'))
                          : RefreshIndicator(
                              onRefresh: _loadDisputes,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) => _buildDisputeCard(filtered[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterStatus = value),
        backgroundColor: Colors.grey.shade200,
        selectedColor: Theme.of(context).primaryColor,
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildDisputeCard(Dispute dispute) {
    final canResolve = dispute.status == DisputeStatus.open || dispute.status == DisputeStatus.inReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Job #${dispute.jobId}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                StatusBadge.outlined(
                  label: AppColors.disputeStatusLabel(dispute.status),
                  color: AppColors.disputeStatusColor(dispute.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            StatusBadge.outlined(
              label: _reasonLabel(dispute.reason),
              color: AppColors.disputeReasonColor(dispute.reason),
            ),
            const SizedBox(height: 8),
            Text(dispute.details, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (dispute.resolution != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(dispute.resolution!, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green)),
                  ),
                ],
              ),
            ],
            if (canResolve) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text('Resolve Dispute'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _resolveDispute(dispute),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}