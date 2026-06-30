// lib/screens/admin_customers_screen.dart
import 'package:artisans_app/widgets/scattered_background_image.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  final AuthApiService _authService = AuthApiService();
  final ArtisanApiService _artisanService = ArtisanApiService();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customers = await _authService.listCustomers(search: _searchQuery.isEmpty ? null : _searchQuery);
      if (mounted) {
        setState(() {
          _customers = customers;
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

  Future<void> _toggleActive(Map<String, dynamic> customer, bool activate) async {
    try {
      final userId = customer['user'] as int;
      await _artisanService.activateUser(userId, isActive: activate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activate ? 'Customer activated!' : 'Customer deactivated.'),
            backgroundColor: activate ? Colors.green : Colors.orange,
          ),
        );
        _loadCustomers();
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
        title: const Text('Customer Management'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCustomers),
        ],
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                  _loadCustomers();
                },
              ),
            ),
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
                              ElevatedButton(onPressed: _loadCustomers, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _customers.isEmpty
                          ? const Center(child: Text('No customers found.'))
                          : RefreshIndicator(
                              onRefresh: _loadCustomers,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: _customers.length,
                                itemBuilder: (context, index) => _buildCustomerCard(_customers[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final isActive = customer['user_is_active'] as bool? ?? false;
    final username = customer['user_username'] as String? ?? 'Unknown';
    final email = customer['user_email'] as String? ?? '';
    final jobCount = customer['job_count'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isActive ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                isActive ? Icons.person : Icons.person_off,
                color: isActive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(username, style: const TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      StatusBadge.outlined(
                        label: isActive ? 'Active' : 'Inactive',
                        color: isActive ? Colors.green : Colors.red,
                      ),
                    ],
                  ),
                  Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('$jobCount booking${jobCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _toggleActive(customer, !isActive),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: Text(isActive ? 'Deactivate' : 'Activate', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}