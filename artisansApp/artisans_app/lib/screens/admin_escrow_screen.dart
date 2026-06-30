// lib/screens/admin_escrow_screen.dart
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/services/payment_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:artisans_app/widgets/empty_state.dart';
import 'package:flutter/material.dart';

class AdminEscrowScreen extends StatefulWidget {
  const AdminEscrowScreen({super.key});

  @override
  State<AdminEscrowScreen> createState() => _AdminEscrowScreenState();
}

class _AdminEscrowScreenState extends State<AdminEscrowScreen> {
  final PaymentApiService _paymentService = PaymentApiService();
  List<Job> _escrowJobs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEscrowJobs();
  }

  Future<void> _loadEscrowJobs() async {
    setState(() => _isLoading = true);
    try {
      final jobs = await _paymentService.adminListEscrowJobs();
      if (mounted) {
        setState(() {
          _escrowJobs = jobs;
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

  Future<void> _releaseEscrow(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release Escrow'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Release ₦${job.escrowHeldAmount.toStringAsFixed(2)} to the artisan?'),
            const SizedBox(height: 8),
            const Text('The artisan will receive the amount minus the 10% commission.'),
            const SizedBox(height: 4),
            Text('Job: ${job.description}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text('Customer: ${job.customerUsername ?? "Unknown"}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text('Artisan: ${job.artisanUsername ?? "Unknown"}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
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

    if (confirmed != true || !mounted) return;

    try {
      await _paymentService.adminReleaseEscrow(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escrow released successfully!'), backgroundColor: Colors.green),
        );
        _loadEscrowJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _refundEscrow(Job job) async {
    final amountController = TextEditingController(text: job.escrowHeldAmount.toStringAsFixed(2));
    bool fullRefund = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Refund Escrow'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escrow held: ₦${job.escrowHeldAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: fullRefund,
                  onChanged: (v) => setDialogState(() => fullRefund = v ?? true),
                  title: const Text('Full refund to customer'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!fullRefund) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Refund amount (₦)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text('Job: ${job.description}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text('Customer: ${job.customerUsername ?? "Unknown"}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                final amount = fullRefund ? null : double.tryParse(amountController.text);
                Navigator.pop(context, {'fullRefund': fullRefund, 'amount': amount});
              },
              child: const Text('Refund', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    try {
      await _paymentService.adminRefundEscrow(
        job.id,
        amount: result['fullRefund'] ? null : result['amount'] as double?,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escrow refunded successfully!'), backgroundColor: Colors.green),
        );
        _loadEscrowJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escrow Management'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEscrowJobs),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _escrowJobs.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadEscrowJobs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _escrowJobs.length,
                        itemBuilder: (context, index) => _buildEscrowCard(_escrowJobs[index]),
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: 'No escrow funds held',
      subtitle: 'When customers fund escrow for jobs, they will appear here for you to manage.',
      action: ElevatedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
        onPressed: _loadEscrowJobs,
      ),
    );
  }

  Widget _buildErrorState() {
    return ErrorState(
      message: _error ?? 'Failed to load escrow data',
      onRetry: _loadEscrowJobs,
    );
  }

  Widget _buildEscrowCard(Job job) {
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
                    maxLines: 1,
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
                const Icon(Icons.account_balance_wallet, size: 16, color: Colors.green),
                Text(
                  ' ₦${job.escrowHeldAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (job.customerUsername != null)
              Text('Customer: ${job.customerUsername}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (job.artisanUsername != null)
              Text('Artisan: ${job.artisanUsername}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Release'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _releaseEscrow(job),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Refund'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    onPressed: () => _refundEscrow(job),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}