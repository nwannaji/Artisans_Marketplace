// lib/screens/wallet_screen.dart
import 'package:artisans_app/models/wallet.dart';
import 'package:artisans_app/models/bank_account.dart';
import 'package:artisans_app/services/payment_api_service.dart';
import 'package:flutter/material.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final PaymentApiService _paymentService = PaymentApiService();
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  List<BankAccount> _bankAccounts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final wallet = await _paymentService.getWallet();
      final transactions = await _paymentService.listTransactions();
      final bankAccounts = await _paymentService.listBankAccounts();
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _transactions = transactions;
          _bankAccounts = bankAccounts;
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
            SnackBar(content: Text('Deposit failed: $e'), backgroundColor: Colors.red),
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
              content: Text('Withdrawal failed: $e'),
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
                      content: Text('Failed to add bank account: $e'),
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

  Color _transactionColor(TransactionType transactionType) {
    switch (transactionType) {
      case TransactionType.deposit: return Colors.green;
      case TransactionType.withdrawal: return Colors.red;
      case TransactionType.transferOut: return Colors.blue;
      case TransactionType.commission: return Colors.orange;
      case TransactionType.refund: return Colors.purple;
      case TransactionType.escrowHold: return Colors.indigo;
      case TransactionType.escrowRelease: return Colors.teal;
    }
  }

  IconData _transactionIcon(TransactionType transactionType) {
    switch (transactionType) {
      case TransactionType.deposit: return Icons.add_circle;
      case TransactionType.withdrawal: return Icons.remove_circle;
      case TransactionType.transferOut: return Icons.outbox;
      case TransactionType.commission: return Icons.percent;
      case TransactionType.refund: return Icons.undo;
      case TransactionType.escrowHold: return Icons.lock;
      case TransactionType.escrowRelease: return Icons.lock_open;
    }
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
                              colors: [Colors.teal.shade600, Colors.teal.shade800],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.teal.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
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
                                        foregroundColor: Colors.teal.shade800,
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
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.teal.shade900,
                                      ),
                                      onPressed: _withdraw,
                                    ),
                                  ),
                                ],
                              ),
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
                                                      SnackBar(content: Text('Verification failed: $e'), backgroundColor: Colors.red),
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
                                  backgroundColor: _transactionColor(tx.transactionType).withValues(alpha: 0.15),
                                  child: Icon(_transactionIcon(tx.transactionType), color: _transactionColor(tx.transactionType), size: 20),
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