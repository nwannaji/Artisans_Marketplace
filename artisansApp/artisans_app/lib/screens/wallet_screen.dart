// lib/screens/wallet_screen.dart
import 'package:artisans_app/models/wallet.dart';
import 'package:artisans_app/models/bank_account.dart';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/screens/escrow_payment_screen.dart';
import 'package:artisans_app/services/payment_api_service.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/services/token_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:artisans_app/widgets/info_callout.dart';
import 'package:artisans_app/widgets/drag_handle.dart';
import 'package:flutter/material.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final PaymentApiService _paymentService = PaymentApiService();
  final BookingApiService _bookingService = BookingApiService();
  final TokenService _tokenService = TokenService();
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  List<BankAccount> _bankAccounts = [];
  List<Job> _activeEscrowJobs = [];
  bool _isLoading = true;
  bool _isLoadingJobs = false;
  bool _isCustomer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _paymentService.getWallet(),
        _paymentService.listTransactions(),
        _paymentService.listBankAccounts(),
        _tokenService.getUserRole(),
      ]);
      final wallet = results[0] as Wallet;
      final transactions = results[1] as List<Transaction>;
      final bankAccounts = results[2] as List<BankAccount>;
      final role = results[3] as String?;
      final isCustomer = role?.toUpperCase() == 'CUSTOMER';

      if (mounted) {
        setState(() {
          _wallet = wallet;
          _transactions = transactions;
          _bankAccounts = bankAccounts;
          _isCustomer = isCustomer;
          _isLoading = false;
          _error = null;
        });
      }

      // Load active escrow jobs in background (customers only)
      if (isCustomer) {
        _loadActiveEscrowJobs();
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

  Future<void> _loadActiveEscrowJobs() async {
    setState(() => _isLoadingJobs = true);
    try {
      // Fetch all active jobs without status filter so we include
      // PENDING and ADMIN_APPROVED bookings that need escrow funding.
      final allJobs = await _bookingService.listJobs();

      // Keep only non-terminal jobs (anything not cancelled, disputed, or rejected)
      final relevantJobs = allJobs.where((job) {
        switch (job.status) {
          case JobStatus.pending:
          case JobStatus.adminApproved:
          case JobStatus.accepted:
          case JobStatus.inProgress:
          case JobStatus.awaitingReview:
          case JobStatus.completed:
            return true;
          case JobStatus.cancelled:
          case JobStatus.disputed:
          case JobStatus.rejected:
            return false;
        }
      }).toList();

      if (mounted) {
        setState(() {
          _activeEscrowJobs = relevantJobs;
          _isLoadingJobs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingJobs = false);
      }
    }
  }

  Future<void> _deposit() async {
    final amountController = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deposit Funds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the amount you want to deposit into your wallet.'),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₦)',
                prefixIcon: Icon(Icons.payments),
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
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                Navigator.pop(context, amount);
              }
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final response = await _paymentService.depositToWallet(amount: result);
        if (mounted) {
          final authUrl = response['authorization_url'] as String?;
          if (authUrl != null) {
            // SECURITY: Validate that the authorization URL is from Paystack
            // to prevent phishing redirects if the API response is tampered with.
            if (!authUrl.startsWith('https://checkout.paystack.co/') &&
                !authUrl.startsWith('https://standard.paystack.co/')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invalid payment URL. Please contact support.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment initialized. Please complete payment in the browser.'),
                backgroundColor: Colors.blue,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Deposit initiated!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deposit failed. Please try again.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _withdraw() async {
    if (_bankAccounts.isEmpty) {
      _showAddBankAccountDialog();
      return;
    }

    final amountController = TextEditingController();
    BankAccount? selectedAccount = _bankAccounts.firstWhere(
      (a) => a.isDefault,
      orElse: () => _bankAccounts.first,
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Withdraw to Bank'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available balance: ₦${(_wallet?.balance ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Minimum withdrawal: ₦100.00',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₦)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BankAccount>(
                    value: selectedAccount,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Bank Account',
                      border: OutlineInputBorder(),
                    ),
                    items: _bankAccounts.map((account) {
                      final last4 = account.accountNumber.length >= 4
                          ? account.accountNumber.substring(account.accountNumber.length - 4)
                          : account.accountNumber;
                      return DropdownMenuItem(
                        value: account,
                        child: Text(
                          '${account.accountName} ••••$last4'
                          '${account.isVerified ? ' ✓' : ' ⚠'}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => selectedAccount = value);
                    },
                  ),
                  if (selectedAccount != null && !selectedAccount!.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'This account is not yet verified. Withdrawal will be held for manual processing.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount >= 100 && selectedAccount != null) {
                  Navigator.pop(context, {
                    'amount': amount,
                    'bank_account_id': selectedAccount!.id,
                  });
                } else if (amount != null && amount < 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Minimum withdrawal is ₦100'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Withdraw'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      try {
        final response = await _paymentService.withdraw(
          amount: result['amount'] as double,
          bankAccountId: result['bank_account_id'] as int,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Withdrawal initiated!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Withdrawal failed. Please try again.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  void _showAddBankAccountDialog() {
    final bankCodeController = TextEditingController();
    final accountNumberController = TextEditingController();
    final accountNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Bank Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add your Nigerian bank account to receive payouts.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: accountNameController,
              decoration: const InputDecoration(
                labelText: 'Account Name',
                hintText: 'Full name as on bank account',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: accountNumberController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Account Number',
                hintText: '10-digit NUBAN account number',
                prefixIcon: Icon(Icons.numbers),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bankCodeController,
              decoration: const InputDecoration(
                labelText: 'Bank Code',
                hintText: 'e.g. 058 for GTBank',
                prefixIcon: Icon(Icons.account_balance),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Common bank codes: GTBank=058, Access=044, UBA=033, First Bank=011, Zenith=057',
              style: TextStyle(fontSize: 11, color: Colors.grey),
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
              if (accountNameController.text.isEmpty ||
                  accountNumberController.text.length != 10 ||
                  bankCodeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in all fields correctly'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context); // Close dialog first
              final messenger = ScaffoldMessenger.of(context);

              try {
                await _paymentService.addBankAccount(
                  bankCode: bankCodeController.text.trim(),
                  accountNumber: accountNumberController.text.trim(),
                  accountName: accountNameController.text.trim(),
                );
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Bank account added! Verification in process.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadData();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Failed to add bank account. Please try again.'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            child: const Text('Add Account'),
          ),
        ],
      ),
    );
  }


  String _escrowActionLabel(Job job) {
    final hasEscrow = job.escrowHeldAmount > 0;
    if (!hasEscrow) {
      if (job.status == JobStatus.pending) return 'Fund Escrow';
      if (job.status == JobStatus.adminApproved) return 'Fund Escrow';
      return 'Fund Escrow';
    }
    if (job.status == JobStatus.awaitingReview ||
        job.status == JobStatus.completed) {
      return 'Release Payment';
    }
    return 'View';
  }

  Color _escrowActionColor(Job job) {
    final hasEscrow = job.escrowHeldAmount > 0;
    if (!hasEscrow) {
      if (job.status == JobStatus.pending) return Colors.amber;
      if (job.status == JobStatus.adminApproved) return Colors.lightBlue;
      return Colors.green;
    }
    if (job.status == JobStatus.awaitingReview ||
        job.status == JobStatus.completed) {
      return AppColors.primary;
    }
    return Colors.grey;
  }

  /// Jobs that haven't funded escrow yet (any active status without escrow held).
  List<Job> get _unfundedJobs => _activeEscrowJobs
      .where((j) => j.escrowHeldAmount == 0 &&
          j.status != JobStatus.completed &&
          j.status != JobStatus.awaitingReview)
      .toList();

  /// Jobs that have escrow funded and may need release.
  List<Job> get _fundedJobs => _activeEscrowJobs
      .where((j) => j.escrowHeldAmount > 0)
      .toList();

  /// Show a bottom sheet listing unfunded jobs so the customer can fund escrow.
  void _showPayViaEscrowSheet() {
    final unfunded = _unfundedJobs;

    if (unfunded.isEmpty && _activeEscrowJobs.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pay via Escrow'),
          content: const Text(
            'No bookings found. Book an artisan first, then fund escrow from here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (unfunded.isEmpty) {
      // All active jobs already have escrow — show helpful message
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pay via Escrow'),
          content: const Text(
            'All your active bookings already have escrow funded. '
            'Check the "Release Payment" section to release funds when the job is done.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            const DragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_user, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pay via Escrow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Your payment is held safely until the job is done',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: unfunded.length,
                itemBuilder: (context, index) {
                  final job = unfunded[index];
                  final artisanName = job.artisanUsername ?? 'Artisan';
                  final isPending = job.status == JobStatus.pending;
                  final isAdminApproved = job.status == JobStatus.adminApproved;
                  final statusHint = isPending
                      ? 'Awaiting admin approval'
                      : isAdminApproved
                          ? 'Awaiting artisan acceptance'
                          : null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(
                                  artisanName[0].toUpperCase(),
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(artisanName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      job.description.length > 50
                                          ? '${job.description.substring(0, 50)}...'
                                          : job.description,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              StatusBadge.outlined(
                                label: job.status.label,
                                color: AppColors.jobStatusColor(job.status),
                              ),
                            ],
                          ),
                          if (statusHint != null) ...[
                            const SizedBox(height: 6),
                            InfoCallout.warning(message: statusHint),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                '₦${job.agreedPrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.lock, size: 16),
                                label: const Text('Fund Escrow'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _escrowActionColor(job),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  Navigator.pop(context); // Close bottom sheet
                                  _navigateToEscrow(job);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to the EscrowPaymentScreen for a given job.
  void _navigateToEscrow(Job job) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EscrowPaymentScreen(
          jobId: job.id,
          agreedPrice: job.agreedPrice,
          job: job,
        ),
      ),
    );
    if (result == true && mounted) {
      _loadData();
    }
  }

  Widget _buildActiveEscrowSection() {
    if (!_isCustomer) return const SizedBox.shrink();

    // Show loading state
    if (_isLoadingJobs) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Escrow',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    // No active escrow jobs
    if (_activeEscrowJobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Escrow',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified_user_outlined, color: Colors.grey),
                title: Text('No active escrow'),
                subtitle: Text('Your escrow payments will appear here when you fund a job.'),
              ),
            ),
          ],
        ),
      );
    }

    final unfunded = _unfundedJobs;
    final funded = _fundedJobs;

    // Separate pending/approved jobs from accepted/in-progress ones
    final pendingJobs = unfunded.where((j) =>
        j.status == JobStatus.pending || j.status == JobStatus.adminApproved).toList();
    final fundableJobs = unfunded.where((j) =>
        j.status == JobStatus.accepted || j.status == JobStatus.inProgress).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Escrow',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Awaiting Confirmation sub-section (PENDING / ADMIN_APPROVED)
          if (pendingJobs.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.amber[700]),
                const SizedBox(width: 4),
                Text(
                  'Awaiting Confirmation',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.amber[700]),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...pendingJobs.map((job) => _buildEscrowJobCard(job)),
            if (fundableJobs.isNotEmpty || funded.isNotEmpty) const SizedBox(height: 12),
          ],

          // Fund Escrow sub-section (ACCEPTED / IN_PROGRESS, no escrow yet)
          if (fundableJobs.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.lock, size: 16, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  'Fund Escrow',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[700]),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...fundableJobs.map((job) => _buildEscrowJobCard(job)),
            if (funded.isNotEmpty) const SizedBox(height: 12),
          ],

          // Release Payment sub-section
          if (funded.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.lock_open, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'Release Payment',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...funded.map((job) => _buildEscrowJobCard(job)),
          ],
        ],
      ),
    );
  }

  Widget _buildEscrowJobCard(Job job) {
    final hasEscrow = job.escrowHeldAmount > 0;
    final actionLabel = _escrowActionLabel(job);
    final actionColor = _escrowActionColor(job);
    final isPending = job.status == JobStatus.pending;
    final isAdminApproved = job.status == JobStatus.adminApproved;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Job #${job.id} — ${job.description.length > 40 ? '${job.description.substring(0, 40)}...' : job.description}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StatusBadge.outlined(
                  label: job.status.label,
                  color: AppColors.jobStatusColor(job.status),
                ),
              ],
            ),
            if (isPending || isAdminApproved) ...[
              const SizedBox(height: 6),
              InfoCallout.warning(
                message: isPending
                    ? 'Awaiting admin approval. Escrow will be held until the artisan accepts.'
                    : 'Awaiting artisan acceptance. Escrow will be held until the job starts.',
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Agreed: ₦${job.agreedPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13),
                ),
                if (hasEscrow) ...[
                  const SizedBox(width: 16),
                  Text(
                    'In escrow: ₦${job.escrowHeldAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  hasEscrow ? Icons.lock_open : Icons.lock,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _navigateToEscrow(job),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
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
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    slivers: [
                      // Balance card
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(
                                '₦${(_wallet?.balance ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Deposit'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.primaryDark,
                                      ),
                                      onPressed: _deposit,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.outbox, size: 18),
                                      label: const Text('Withdraw'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: AppColors.primaryDark,
                                      ),
                                      onPressed: _withdraw,
                                    ),
                                  ),
                                ],
                              ),
                              if (_isCustomer) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.verified_user, size: 18),
                                    label: const Text('Pay via Escrow'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _isLoadingJobs ? null : _showPayViaEscrowSheet,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Bank Accounts section
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Bank Accounts',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add'),
                                onPressed: _showAddBankAccountDialog,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _bankAccounts.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.account_balance_outlined, color: Colors.grey),
                                    title: const Text('No bank accounts added'),
                                    subtitle: const Text('Add a bank account to withdraw funds'),
                                    trailing: ElevatedButton(
                                      onPressed: _showAddBankAccountDialog,
                                      child: const Text('Add'),
                                    ),
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Column(
                                  children: _bankAccounts.map((account) => Card(
                                    child: ListTile(
                                      leading: Icon(
                                        account.isVerified ? Icons.verified : Icons.warning_amber,
                                        color: account.isVerified ? Colors.green : Colors.orange,
                                      ),
                                      title: Text(account.accountName),
                                      subtitle: Text(
                                        '****${account.accountNumber.substring(account.accountNumber.length - 4)} · Bank: ${account.bankCode}'
                                        '${account.isDefault ? ' · Default' : ''}',
                                      ),
                                      trailing: account.isVerified
                                          ? const Text('Verified', style: TextStyle(color: Colors.green, fontSize: 12))
                                          : TextButton(
                                              onPressed: () async {
                                                final messenger = ScaffoldMessenger.of(context);
                                                try {
                                                  await _paymentService.verifyBankAccount(account.id);
                                                  if (mounted) {
                                                    messenger.showSnackBar(
                                                      const SnackBar(content: Text('Bank account verified!'), backgroundColor: Colors.green),
                                                    );
                                                    _loadData();
                                                  }
                                                } catch (e) {
                                                  if (mounted) {
                                                    messenger.showSnackBar(
                                                      const SnackBar(content: Text('Verification failed. Please try again.'), backgroundColor: Colors.red),
                                                    );
                                                  }
                                                }
                                              },
                                              child: const Text('Verify'),
                                            ),
                                    ),
                                  )).toList(),
                                ),
                              ),
                      ),

                      // Active Escrow section (customers only)
                      SliverToBoxAdapter(child: _buildActiveEscrowSection()),

                      // Transactions header
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Transactions',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      // Transaction list
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = _transactions[index];
                            final isCredit = tx.transactionType == TransactionType.deposit ||
                                tx.transactionType == TransactionType.refund ||
                                tx.transactionType == TransactionType.escrowRelease;
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.transactionColor(tx.transactionType).withValues(alpha: 0.15),
                                  child: Icon(AppColors.transactionIcon(tx.transactionType), color: AppColors.transactionColor(tx.transactionType), size: 20),
                                ),
                                title: Text(
                                  tx.transactionType.label,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  tx.description ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isCredit ? "+" : "-"}₦${tx.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isCredit ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      tx.status,
                                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _transactions.length,
                        ),
                      ),
                      if (_transactions.isEmpty)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('No transactions yet.'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}