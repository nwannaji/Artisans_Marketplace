import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/widgets/profile_avatar.dart';
import 'package:artisans_app/widgets/scattered_background_image.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/status_badge.dart';
import 'package:artisans_app/widgets/drag_handle.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<Job> _pendingJobs = [];
  List<Artisan> _artisans = [];
  bool _isLoadingJobs = true;
  String? _jobsError;
  final Set<int> _actionInProgress = {};

  final BookingApiService _bookingService = BookingApiService();
  final ArtisanApiService _artisanService = ArtisanApiService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _loadPendingJobs();
    _loadArtisans();
  }

  Future<void> _loadPendingJobs() async {
    setState(() => _isLoadingJobs = true);
    try {
      _pendingJobs = await _bookingService.listJobs(status: 'PENDING');
      setState(() { _isLoadingJobs = false; _jobsError = null; });
    } catch (e) {
      setState(() { _isLoadingJobs = false; _jobsError = e.toString(); });
    }
  }

  Future<void> _loadArtisans() async {
    try {
      final artisans = await _artisanService.listArtisans(includeInactive: true);
      setState(() => _artisans = artisans);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load artisans: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _approveJob(int jobId) async {
    try {
      await _bookingService.approveJob(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job approved successfully!'), backgroundColor: Colors.green),
      );
      _loadPendingJobs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectJob(int jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Job?'),
        content: const Text('This will reject the job. The customer will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _bookingService.rejectJob(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job rejected.'), backgroundColor: Colors.orange),
      );
      _loadPendingJobs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _verifyArtisan(int pk, bool verified) async {
    setState(() => _actionInProgress.add(pk));
    try {
      final updated = await _artisanService.verifyArtisan(pk, verified: verified);
      if (!mounted) return;
      final index = _artisans.indexWhere((a) => a.id == pk);
      if (index != -1) _artisans[index] = updated;
      setState(() => _actionInProgress.remove(pk));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(verified ? 'Artisan verified!' : 'Verification revoked.'),
          backgroundColor: verified ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionInProgress.remove(pk));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleUserActive(Artisan artisan, bool activate) async {
    setState(() => _actionInProgress.add(artisan.id));
    try {
      await _artisanService.activateUser(artisan.userId, isActive: activate);
      if (!mounted) return;
      final index = _artisans.indexWhere((a) => a.id == artisan.id);
      if (index != -1) {
        _artisans[index] = _artisans[index].copyWith(userIsActive: activate);
      }
      setState(() => _actionInProgress.remove(artisan.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(activate ? 'Account activated!' : 'Account deactivated.'),
          backgroundColor: activate ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionInProgress.remove(artisan.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _logout() async {
    final authViewModel = context.read<AuthViewModel>();
    await authViewModel.signOut();
    if (mounted) {
      // Clear the entire navigation stack so the user can't go back
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _showArtisanDetails(Artisan artisan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              const DragHandle(),
              // Header
              Row(
                children: [
                  ProfileAvatar(
                    imageUrl: artisan.profilePicture,
                    name: artisan.fullName,
                    radius: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(artisan.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                            if (artisan.isVerified)
                              const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 18, color: AppColors.verifiedBlue)),
                          ],
                        ),
                        Text(artisan.profession ?? 'No profession set', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Status badges
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge.outlined(
                    label: artisan.userIsActive ? 'Active' : 'Inactive',
                    color: artisan.userIsActive ? Colors.green : Colors.red,
                  ),
                  StatusBadge.outlined(
                    label: artisan.isVerified ? 'Verified' : 'Unverified',
                    color: artisan.isVerified ? AppColors.verifiedBlue : Colors.orange,
                  ),
                  StatusBadge.outlined(
                    label: artisan.availabilityLabel,
                    color: artisan.isAvailableNow ? Colors.green : (artisan.isEngaged ? AppColors.primary : (artisan.isAvailable == 'BUSY' ? Colors.orange : Colors.grey)),
                  ),
                ],
              ),
              const Divider(height: 24),
              // Details
              _buildDetailRow(Icons.star, 'Rating', '${artisan.rating.toStringAsFixed(1)} (${artisan.reviewCount} reviews)'),
              _buildDetailRow(Icons.work, 'Jobs completed', '${artisan.jobsCompleted}'),
              if (artisan.hourlyRate != null)
                _buildDetailRow(Icons.payment, 'Hourly rate', '₦${artisan.hourlyRate!.toStringAsFixed(0)}/hr'),
              if (artisan.location != null)
                _buildDetailRow(Icons.location_on, 'Location', artisan.location!),
              if (artisan.latitude != null && artisan.longitude != null && artisan.location == null)
                _buildDetailRow(Icons.my_location, 'Coordinates', '${artisan.latitude!.toStringAsFixed(4)}, ${artisan.longitude!.toStringAsFixed(4)}'),
              if (artisan.bio != null && artisan.bio!.isNotEmpty)
                _buildDetailRow(Icons.description, 'Bio', artisan.bio!),
              if (artisan.skills.isNotEmpty)
                _buildDetailRow(Icons.build, 'Skills', artisan.skills.cast<String>().join(', ')),
              const Divider(height: 24),
              // Admin actions
              const Text('Admin Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // Activate / Deactivate
              SizedBox(
                width: double.infinity,
                child: artisan.userIsActive
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Deactivate Account'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _confirmAction(
                            title: 'Deactivate ${artisan.fullName}?',
                            message: 'This will prevent the artisan from logging in. They can be reactivated later.',
                            confirmLabel: 'Deactivate',
                            confirmColor: Colors.red,
                            onConfirm: () => _toggleUserActive(artisan, false),
                          );
                        },
                      )
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Activate Account'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _toggleUserActive(artisan, true),
                      ),
              ),
              const SizedBox(height: 8),
              // Verify / Revoke verification
              if (artisan.userIsActive) ...[
                SizedBox(
                  width: double.infinity,
                  child: artisan.isVerified
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Revoke Verification'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmAction(
                              title: 'Revoke verification for ${artisan.fullName}?',
                              message: 'This artisan will no longer show as verified.',
                              confirmLabel: 'Revoke',
                              confirmColor: Colors.orange,
                              onConfirm: () => _verifyArtisan(artisan.id, false),
                            );
                          },
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Verify'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => _verifyArtisan(artisan.id, true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _confirmAction(
                                    title: 'Reject ${artisan.fullName}?',
                                    message: 'This will mark the artisan as unverified.',
                                    confirmLabel: 'Reject',
                                    confirmColor: Colors.red,
                                    onConfirm: () => _verifyArtisan(artisan.id, false),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (result == true) onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final pendingActivation = _artisans.where((a) => !a.userIsActive).toList();
    final unverified = _artisans.where((a) => a.userIsActive && !a.isVerified).toList();
    final verified = _artisans.where((a) => a.userIsActive && a.isVerified).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          Consumer<AuthViewModel>(
            builder: (context, auth, _) => auth.currentUser != null
                ? IconButton(icon: const Icon(Icons.logout), onPressed: _logout)
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats summary
                _buildStatsRow(pendingActivation.length, unverified.length, verified.length),
                const SizedBox(height: 20),
                // Admin management cards
                _buildManagementCards(),
                const SizedBox(height: 20),
                _buildPendingJobs(),
                const SizedBox(height: 20),
                _buildArtisanSection('Pending Activation', pendingActivation, Colors.red),
                _buildArtisanSection('Awaiting Verification', unverified, Colors.orange),
                _buildArtisanSection('Verified Artisans', verified, Colors.green),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagementCards() {
    final cards = [
      _ManagementCard(icon: Icons.people, label: 'Customer\nManagement', color: AppColors.primary, route: '/admin_customers'),
      _ManagementCard(icon: Icons.gavel, label: 'Dispute\nManagement', color: Colors.red, route: '/admin_disputes'),
      _ManagementCard(icon: Icons.chat, label: 'Chat\nMediation', color: AppColors.primary, route: '/admin_chat'),
    ];
    return Row(
      children: cards.map((card) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pushNamed(context, card.route),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  children: [
                    Icon(card.icon, color: card.color, size: 28),
                    const SizedBox(height: 6),
                    Text(card.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildStatsRow(int pending, int unverified, int verified) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Pending', pending, Colors.red)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Unverified', unverified, Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Verified', verified, Colors.green)),
      ],
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingJobs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Pending Job Approvals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_isLoadingJobs) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((255 * 0.5).round()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _jobsError != null
              ? ListTile(title: Text('Error: $_jobsError'))
              : _pendingJobs.isEmpty
                  ? const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('No pending jobs'),
                    )
                  : ListView.builder(
                      itemCount: _pendingJobs.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final job = _pendingJobs[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.work, color: Colors.orange),
                            title: Text(job.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '₦${job.agreedPrice.toStringAsFixed(0)} | ${job.customerUsername ?? "Customer"} → ${job.artisanUsername ?? "Artisan"}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  onPressed: () => _approveJob(job.id),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  child: const Text('Approve', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 4),
                                ElevatedButton(
                                  onPressed: () => _rejectJob(job.id),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildArtisanSection(String title, List<Artisan> artisans, Color color) {
    if (artisans.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            '$title (${artisans.length})',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ),
        ...artisans.map((a) => _buildArtisanCard(a)),
      ],
    );
  }

  Widget _buildArtisanCard(Artisan artisan) {
    final isActing = _actionInProgress.contains(artisan.id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showArtisanDetails(artisan),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              ProfileAvatar(
                imageUrl: artisan.profilePicture,
                name: artisan.fullName,
                radius: 22,
                backgroundColor: !artisan.userIsActive
                    ? Colors.red.shade100
                    : artisan.isVerified
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                foregroundColor: !artisan.userIsActive
                    ? Colors.red.shade700
                    : artisan.isVerified
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(artisan.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (artisan.isVerified)
                          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: AppColors.verifiedBlue)),
                        if (!artisan.userIsActive)
                          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.lock_outline, size: 16, color: Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${artisan.profession ?? "No profession"} | ★ ${artisan.rating.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Quick action + chevron
              if (isActing)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (!artisan.userIsActive)
                ElevatedButton(
                  onPressed: () => _toggleUserActive(artisan, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Activate', style: TextStyle(fontSize: 12)),
                )
              else
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagementCard {
  final IconData icon;
  final String label;
  final Color color;
  final String route;

  _ManagementCard({required this.icon, required this.label, required this.color, required this.route});
}