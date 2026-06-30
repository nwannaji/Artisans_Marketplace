// lib/screens/booking_history_screen.dart
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/screens/dispute_screen.dart';
import 'package:artisans_app/screens/escrow_payment_screen.dart';
import 'package:artisans_app/widgets/rating_selector.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:artisans_app/widgets/info_callout.dart';
import 'package:flutter/material.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  List<Job> _jobs = [];
  bool _isLoading = true;
  String? _error;
  String _filterStatus = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      _jobs = await BookingApiService().listJobs();
      setState(() { _isLoading = false; _error = null; });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _completeJob(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Job'),
        content: const Text('Are you sure you want to mark this job as completed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await BookingApiService().updateJobStatus(job.id, 'COMPLETED');
      if (!mounted) return;

      final escrowReleased = response['escrow_released'] == true;
      final otpRequired = response['escrow_release_otp_required'] == true;

      if (otpRequired) {
        // Escrow requires OTP — navigate to EscrowPaymentScreen for OTP entry
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job marked as completed! Payment requires OTP confirmation.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        final escrowResult = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => EscrowPaymentScreen(
              jobId: job.id,
              agreedPrice: job.agreedPrice,
              job: job,
            ),
          ),
        );
        if (!mounted) return;
        if (escrowResult == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment released to artisan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadJobs();
        return;
      }

      // Prompt for rating after completing the job
      final rated = await _showRatingDialog(job);

      if (!mounted) return;
      String message = rated ? 'Job completed and rated!' : 'Job marked as completed!';
      if (escrowReleased) {
        message = rated ? 'Job completed, rated, and payment released!' : 'Job completed! Payment released to artisan.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
      _loadJobs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to complete job. Please try again.'), backgroundColor: Colors.red),
      );
    }
  }

  /// Show a rating dialog after completing a job. Returns true if rated.
  Future<bool> _showRatingDialog(Job job) async {
    double selectedRating = 0;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate this artisan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.artisanUsername != null)
                  Text('Rate ${job.artisanUsername}\'s work',
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 16),
                RatingSelector(
                  initialRating: 0,
                  onRatingSelected: (rating) {
                    setDialogState(() => selectedRating = rating);
                  },
                  starSize: 36,
                  showLabel: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review (optional)',
                    hintText: 'How was your experience?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: selectedRating == 0 ? null : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit Rating'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedRating > 0) {
      try {
        await BookingApiService().rateJob(
          job.id,
          selectedRating,
          review: reviewController.text,
        );
        return true;
      } catch (_) {
        // Rating failed silently — job is still completed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rating could not be submitted. You can rate later from your booking history.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
    return false;
  }

  /// Allow rating a completed job that hasn't been rated yet.
  Future<void> _rateCompletedJob(Job job) async {
    double selectedRating = 0;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate this artisan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.artisanUsername != null)
                  Text('Rate ${job.artisanUsername}\'s work',
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 16),
                RatingSelector(
                  initialRating: 0,
                  onRatingSelected: (rating) {
                    setDialogState(() => selectedRating = rating);
                  },
                  starSize: 36,
                  showLabel: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review (optional)',
                    hintText: 'How was your experience?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
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
              onPressed: selectedRating == 0 ? null : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedRating > 0) {
      try {
        await BookingApiService().rateJob(
          job.id,
          selectedRating,
          review: reviewController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted!'), backgroundColor: Colors.green),
        );
        _loadJobs();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit rating. Please try again.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Job> get _filteredJobs {
    if (_filterStatus == 'ALL') return _jobs;
    return _jobs.where((j) => j.status.toApiString() == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredJobs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadJobs),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('ALL'),
                _buildFilterChip('PENDING'),
                _buildFilterChip('ADMIN_APPROVED'),
                _buildFilterChip('ACCEPTED'),
                _buildFilterChip('IN_PROGRESS'),
                _buildFilterChip('AWAITING_REVIEW'),
                _buildFilterChip('COMPLETED'),
                _buildFilterChip('CANCELLED'),
                _buildFilterChip('DISPUTED'),
                _buildFilterChip('REJECTED'),
              ],
            ),
          ),
          // Job list
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
                            ElevatedButton(onPressed: _loadJobs, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? const Center(child: Text('No bookings found.'))
                        : RefreshIndicator(
                            onRefresh: _loadJobs,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) => _buildJobCard(filtered[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filterStatus == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label.replaceAll('_', ' ')),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterStatus = label),
        backgroundColor: Colors.grey.shade200,
        selectedColor: Theme.of(context).primaryColor,
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildJobCard(Job job) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    job.description,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusBadge.filled(
                  label: job.status.label,
                  color: AppColors.jobStatusColor(job.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 16, color: Colors.green),
                Text(' ${job.agreedPrice.toStringAsFixed(0)}'),
                if (job.location != null) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.location_on, size: 16, color: Colors.red),
                  Text(' ${job.location!}', style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
            if (job.escrowHeldAmount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 16, color: Colors.indigo),
                  Text(' Escrow: ₦${job.escrowHeldAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
            if (job.artisanUsername != null) ...[
              const SizedBox(height: 4),
              Text('Artisan: ${job.artisanUsername}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (job.customerUsername != null && job.artisanUsername == null) ...[
              const SizedBox(height: 4),
              Text('Customer: ${job.customerUsername}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],

            // Rating display for completed & rated jobs
            if (job.status == JobStatus.completed && job.rating != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StarRatingDisplay(rating: job.rating!, starSize: 18),
                    if (job.review != null && job.review!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '"${job.review!}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Rate button for completed but unrated jobs
            if (job.status == JobStatus.completed && job.rating == null && job.artisanId != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.star_border, size: 16),
                label: const Text('Rate this artisan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber[800],
                  side: BorderSide(color: Colors.amber[800]!),
                ),
                onPressed: () => _rateCompletedJob(job),
              ),
            ],

            // File Dispute button for in-progress, awaiting review, completed, or disputed jobs
            if (job.status == JobStatus.inProgress ||
                job.status == JobStatus.awaitingReview ||
                job.status == JobStatus.completed ||
                job.status == JobStatus.disputed) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.gavel, size: 16),
                label: const Text('File Dispute'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.pink[700],
                  side: BorderSide(color: Colors.pink[700]!),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DisputeScreen(jobId: job.id)),
                  ).then((_) => _loadJobs());
                },
              ),
            ],

            // Fund escrow — available when job is active and has no escrow yet
            if ((job.status == JobStatus.pending ||
                    job.status == JobStatus.adminApproved ||
                    job.status == JobStatus.accepted ||
                    job.status == JobStatus.inProgress) &&
                job.escrowHeldAmount == 0) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Fund Escrow'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                  ).then((_) => _loadJobs());
                },
              ),
            ],
            // Awaiting review — customer can approve (release escrow) or dispute
            if (job.status == JobStatus.awaitingReview) ...[
              const SizedBox(height: 8),
              InfoCallout.info(message: 'The artisan has marked this job as done. Review and approve to release payment.'),
              if (job.escrowHeldAmount > 0) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Approve & Pay'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                    ).then((_) => _loadJobs());
                  },
                ),
              ] else ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Approve Completion'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () => _completeJob(job),
                ),
              ],
            ],
            // Release payment — available when job is completed and escrow is still held (admin edge case)
            if (job.status == JobStatus.completed && job.escrowHeldAmount > 0) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Release Payment'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                  ).then((_) => _loadJobs());
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}