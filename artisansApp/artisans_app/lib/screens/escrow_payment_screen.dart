// lib/screens/escrow_payment_screen.dart
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/viewmodels/payment_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  bool _isLoading = false;
  bool _isFetchingJob = true;
  Job? _job;

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
    super.dispose();
  }

  Future<void> _fundEscrow() async {
    setState(() => _isLoading = true);
    final viewModel = Provider.of<PaymentViewModel>(context, listen: false);
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      setState(() => _isLoading = false);
      return;
    }

    final success = await viewModel.fundEscrow(widget.jobId, amount: amount);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
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
    final success = await viewModel.releaseEscrow(widget.jobId);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
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
    final canFund = (job.status == JobStatus.accepted || job.status == JobStatus.inProgress) && !hasEscrow;
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (canFund) ...[
              const Text('Fund Escrow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₦)',
                  prefixIcon: Icon(Icons.payments),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _fundEscrow,
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
                  onPressed: _isLoading ? null : _releaseEscrow,
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