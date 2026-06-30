// lib/screens/escrow_payment_screen.dart
import 'dart:async';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/models/wallet.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/viewmodels/payment_view_model.dart';
import 'package:artisans_app/widgets/info_callout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class EscrowPaymentScreen extends StatefulWidget {
  final int jobId;
  final double agreedPrice;
  final Job? job; // Optional: pass full job if already available

  const EscrowPaymentScreen({
    super.key,
    required this.jobId,
    required this.agreedPrice,
    this.job,
  });

  @override
  State<EscrowPaymentScreen> createState() => _EscrowPaymentScreenState();
}

class _EscrowPaymentScreenState extends State<EscrowPaymentScreen> {
  final _amountController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isFetchingJob = true;
  bool _isPolling = false;
  Job? _job;
  PandascrowEscrow? _pandascrowEscrow;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.job != null) {
      _job = widget.job;
      _amountController.text = _job!.agreedPrice.toStringAsFixed(2);
      _isFetchingJob = false;
    } else {
      _fetchJob();
    }
  }

  Future<void> _fetchJob() async {
    try {
      _job = await BookingApiService().getJob(widget.jobId);
      _amountController.text = _job!.agreedPrice.toStringAsFixed(2);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load job details: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isFetchingJob = false);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _otpController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fundEscrow() async {
    setState(() => _isLoading = true);
    final viewModel = Provider.of<PaymentViewModel>(context, listen: false);
    // SECURITY: Use the agreed price directly — the amount field is read-only
    // to prevent manipulation. The server also validates the amount matches.
    final amount = _job!.agreedPrice;

    final result = await viewModel.fundEscrow(widget.jobId, amount: amount);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != null && result['requires_pandascrow_payment'] == true) {
      // Pandascrow escrow flow — open payment URL and start polling
      final paymentUrl = result['payment_url'] as String?;
      if (paymentUrl != null && paymentUrl.isNotEmpty) {
        final uri = Uri.tryParse(paymentUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      _startPollingEscrowStatus();
    } else if (result != null) {
      // Internal escrow funded successfully
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escrow funded successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${viewModel.errorMessage ?? "Unknown error"}'), backgroundColor: Colors.red),
      );
    }
  }

  void _startPollingEscrowStatus() {
    setState(() => _isPolling = true);

    // Show a waiting dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Waiting for Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Waiting for payment confirmation...'),
              const SizedBox(height: 8),
              Text(
                'Complete the payment in your browser, then come back.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _pollingTimer?.cancel();
                _pollingTimer = null;
                setState(() => _isPolling = false);
                Navigator.pop(context); // close dialog
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final viewModel = Provider.of<PaymentViewModel>(context, listen: false);
      final status = await viewModel.getEscrowStatus(widget.jobId);
      if (status != null) {
        final escrowData = PandascrowEscrow.fromJson(status);
        setState(() {
          _pandascrowEscrow = escrowData;
        });
        if (escrowData.status == PandascrowEscrowStatus.funded) {
          timer.cancel();
          _pollingTimer = null;
          setState(() => _isPolling = false);
          if (mounted) {
            Navigator.pop(context); // close waiting dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Escrow funded successfully!'), backgroundColor: Colors.green),
            );
            Navigator.pop(context, true); // pop the screen
          }
        } else if (escrowData.status == PandascrowEscrowStatus.cancelled ||
            escrowData.status == PandascrowEscrowStatus.refunded) {
          timer.cancel();
          _pollingTimer = null;
          setState(() => _isPolling = false);
          if (mounted) {
            Navigator.pop(context); // close waiting dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment ${escrowData.status.label.toLowerCase()}. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    });
  }

  Future<void> _releaseEscrow() async {
    if (_job == null) return;
    final viewModel = Provider.of<PaymentViewModel>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release Escrow'),
        content: Text(
          'Are you sure you want to release ₦${_job!.escrowHeldAmount.toStringAsFixed(2)} '
          'to the artisan? This confirms the job is completed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Release', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final result = await viewModel.releaseEscrow(widget.jobId);

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Check if OTP is required (Pandascrow flow)
    if (result != null && result['otp_required'] == true) {
      _showOtpDialog();
    } else if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escrow released successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${viewModel.errorMessage ?? "Unknown error"}'), backgroundColor: Colors.red),
      );
    }
  }

  void _showOtpDialog() {
    _otpController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('An OTP has been sent to confirm the escrow release. Please enter it below.'),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP Code',
                prefixIcon: Icon(Icons.pin),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final otp = _otpController.text.trim();
              if (otp.isEmpty) return;
              // Capture references before closing the dialog (which invalidates the dialog context)
              final viewModel = Provider.of<PaymentViewModel>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              Navigator.pop(context); // close dialog
              setState(() => _isLoading = true);
              final success = await viewModel.releaseEscrowWithOtp(widget.jobId, otp);

              if (!mounted) return;
              setState(() => _isLoading = false);

              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Escrow released successfully!'), backgroundColor: Colors.green),
                );
                navigator.pop(true);
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('OTP verification failed: ${viewModel.errorMessage ?? "Unknown error"}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Submit OTP'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingJob) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escrow Payment')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escrow Payment')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load job details.'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final job = _job!;
    final hasEscrow = job.escrowHeldAmount > 0;
    final canFund = (job.status == JobStatus.pending ||
          job.status == JobStatus.adminApproved ||
          job.status == JobStatus.accepted ||
          job.status == JobStatus.inProgress) && !hasEscrow;
    final canRelease = (job.status == JobStatus.inProgress || job.status == JobStatus.awaitingReview || job.status == JobStatus.completed) && hasEscrow;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escrow Payment'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Job #${job.id}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Description: ${job.description}'),
                    Text('Agreed Price: ₦${job.agreedPrice.toStringAsFixed(2)}'),
                    Text('Status: ${job.status.label}'),
                    if (hasEscrow) ...[
                      const Divider(),
                      Text(
                        'Escrow Held: ₦${job.escrowHeldAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                    if (_pandascrowEscrow != null) ...[
                      const Divider(),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _pandascrowEscrow!.status.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Escrow: ${_pandascrowEscrow!.status.label}',
                              style: TextStyle(
                                color: _pandascrowEscrow!.status.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (canFund) ...[
              const Text('Fund Escrow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (job.status == JobStatus.pending || job.status == JobStatus.adminApproved)
                InfoCallout.warning(
                  message: job.status == JobStatus.pending
                      ? 'This booking is awaiting admin approval. Your payment will be held in escrow until the artisan accepts.'
                      : 'This booking is awaiting artisan acceptance. Your payment will be held in escrow until the artisan starts the job.',
                ),
              if (job.status == JobStatus.pending || job.status == JobStatus.adminApproved)
                const SizedBox(height: 12),
              // SECURITY: Amount is read-only — displays the agreed price.
              // The server validates that the amount matches the agreed price.
              // This prevents clients from funding escrow with arbitrary amounts.
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Amount (₦)',
                  prefixIcon: Icon(Icons.payments),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  '₦${_job!.agreedPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isPolling) ? null : _fundEscrow,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Fund Escrow'),
                ),
              ),
            ] else if (canRelease) ...[
              const Text('Release Escrow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                job.status == JobStatus.awaitingReview
                    ? 'The artisan has marked this job as done. Approve by releasing payment to the artisan.'
                    : job.status == JobStatus.completed
                        ? 'The job is completed and escrow is held. Release the funds to the artisan now.'
                        : 'The escrow is held. Confirm the job is completed first, then release payment.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isPolling) ? null : _releaseEscrow,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Release Escrow to Artisan'),
                ),
              ),
            ] else ...[
              Card(
                color: Colors.grey.shade200,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.info_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        hasEscrow
                            ? 'Escrow is held. Waiting for job completion to release.'
                            : 'Escrow is not available for this job status (${job.status.label}).',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}