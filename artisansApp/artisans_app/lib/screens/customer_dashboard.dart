import 'package:artisans_app/services/auth_service.dart';
import 'package:artisans_app/services/payment_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../models/job.dart';
import 'search_artisans.dart';
import 'job_detail.dart';

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key});

  @override
  CustomerDashboardScreenState createState() => CustomerDashboardScreenState();
}

class CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  int _selectedIndex = 0;
  late Future<List<Job>> _jobsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _jobsFuture = _apiService.getJobsForUser(authService.user!.uid);
  }

  Future<void> _refreshJobs() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _jobsFuture = _apiService.getJobsForUser(authService.user!.uid);
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Customer Dashboard'),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: Icon(Icons.search),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchArtisansScreen(),
                  ),
                );
              },
            ),
          IconButton(icon: Icon(Icons.refresh), onPressed: _refreshJobs),
        ],
      ),
      body: _selectedIndex == 0 ? _buildJobsList() : _buildWalletSection(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.work), label: 'My Jobs'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildJobsList() {
    return FutureBuilder<List<Job>>(
      future: _jobsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error loading jobs'));
        }

        final jobs = snapshot.data ?? [];

        if (jobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('No jobs found'),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchArtisansScreen(),
                      ),
                    );
                  },
                  child: Text('Find an Artisan'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshJobs,
          child: ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return ListTile(
                title: Text(job.description),
                subtitle: Text(
                  '${DateFormat.yMMMd().format(job.scheduledTime)} - ${job.location}',
                ),
                trailing: Chip(
                  label: Text(job.status.toString().split('.').last),
                  backgroundColor: _getStatusColor(job.status),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JobDetailScreen(job: job),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWalletSection() {
    final paymentService = Provider.of<PaymentService>(context);
    final authService = Provider.of<AuthService>(context);

    return FutureBuilder<double>(
      future: paymentService.getWalletBalance(authService.user!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final balance = snapshot.data ?? 0.0;

        return Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Wallet Balance',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '\$${balance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _showTopUpDialog(context, authService.user!.uid);
                },
                child: Text('Top Up Wallet'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTopUpDialog(BuildContext context, String userId) {
    final amountController = TextEditingController();
    final paymentService = Provider.of<PaymentService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Top Up Wallet'),
          content: TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Amount', prefixText: '\$'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                try {
                  await paymentService.topUpWallet(userId, amount);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Wallet topped up successfully')),
                    );
                  }
                  setState(() {});
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error topping up wallet')),
                    );
                  }
                }
              },
              child: Text('Top Up'),
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.scheduled:
        return Colors.blue;
      case JobStatus.inProgress:
        return Colors.orange;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.cancelled:
        return Colors.red;
      case JobStatus.disputed:
        return Colors.purple;
    }
  }
}
