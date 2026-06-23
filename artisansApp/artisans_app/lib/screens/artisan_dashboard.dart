import 'dart:async';
import 'dart:io';
import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/screens/edit_artisan_profile_screen.dart';
import 'package:artisans_app/screens/escrow_payment_screen.dart';
import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:artisans_app/viewmodels/profile_view_model.dart';

class ArtisanDashboardScreen extends StatefulWidget {
  const ArtisanDashboardScreen({super.key});

  @override
  State<ArtisanDashboardScreen> createState() => _ArtisanDashboardScreenState();
}

class _ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> {
  List<Job> _jobs = [];
  Artisan? _artisanProfile;
  bool _isLoading = true;
  String? _error;
  int? _userId;
  bool _isTogglingAvailability = false;
  bool _isUploadingPicture = false;
  Timer? _gpsUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _gpsUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _userId = await AuthApiService().getUserId();
      if (_userId != null) {
        final bookingService = BookingApiService();
        _jobs = await bookingService.listJobs();
        // Try to load artisan profile
        try {
          final profiles = await ArtisanApiService().listArtisans();
          final mine = profiles.where((a) => a.userId == _userId).toList();
          if (mine.isNotEmpty) {
            _artisanProfile = mine.first;
            // If artisan is available, update their GPS location on app open
            if (_artisanProfile!.isAvailableNow) {
              _updateLocationSilently();
            }
          }
        } catch (_) {
          // Profile may not exist yet, that's okay
        }
      }
      setState(() { _isLoading = false; _error = null; });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  /// Silently update artisan's GPS location without showing errors to the user
  Future<void> _updateLocationSilently() async {
    try {
      final locationService = LocationService();
      final result = await locationService.getCurrentLocationWithAddress();
      if (result != null) {
        await ArtisanApiService().toggleAvailability(
          _artisanProfile?.isAvailable ?? 'OFFLINE',
          latitude: result.latitude,
          longitude: result.longitude,
          location: result.address,
        );
      }
    } catch (_) {
      // Location not available, that's okay — don't disrupt the user
    }
  }

  Future<void> _pickAndUploadPicture(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isUploadingPicture = true);
    try {
      final authService = AuthApiService();
      await authService.uploadProfilePicture(File(pickedFile.path));

      if (!mounted) return;
      // Refresh profile to get the updated photo URL
      await _loadData();
      // Also refresh the ProfileViewModel so the profile screen stays in sync
      if (mounted) {
        try {
          Provider.of<ProfileViewModel>(context, listen: false).fetchUserProfile();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload picture: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPicture = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Change Profile Picture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadPicture(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadPicture(ImageSource.camera);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAvailability(String newStatus) async {
    if (_isTogglingAvailability) return;
    setState(() => _isTogglingAvailability = true);
    try {
      // Get current GPS location with reverse-geocoded address
      double? lat, lng;
      String? locationName;
      try {
        final locationService = LocationService();
        final result = await locationService.getCurrentLocationWithAddress();
        if (result != null) {
          lat = result.latitude;
          lng = result.longitude;
          locationName = result.address;
        }
      } catch (_) {
        // Location not available — toggle without coordinates
      }

      final result = await ArtisanApiService().toggleAvailability(
        newStatus,
        latitude: lat,
        longitude: lng,
        location: locationName,
      );
      if (!mounted) return;
      setState(() {
        _artisanProfile = _artisanProfile?.copyWith(isAvailable: result) ?? _artisanProfile;
        _isTogglingAvailability = false;
      });

      // Start or stop periodic GPS updates based on availability
      if (result == 'AVAILABLE') {
        _startGpsUpdates();
      } else {
        _stopGpsUpdates();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to ${_availabilityLabel(result)}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTogglingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _availabilityLabel(String status) {
    switch (status) {
      case 'AVAILABLE':
        return 'Available';
      case 'ENGAGED':
        return 'Engaged';
      case 'BUSY':
        return 'Busy';
      case 'OFFLINE':
        return 'Offline';
      default:
        return status;
    }
  }

  /// Start periodic GPS updates every 30 seconds while available
  void _startGpsUpdates() {
    _stopGpsUpdates();
    _gpsUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final locationService = LocationService();
        final result = await locationService.getCurrentLocationWithAddress();
        if (result != null && mounted) {
          await ArtisanApiService().updateLocation(
            latitude: result.latitude,
            longitude: result.longitude,
            location: result.address,
          );
        }
      } catch (_) {
        // Silently ignore GPS update failures
      }
    });
  }

  /// Stop periodic GPS updates
  void _stopGpsUpdates() {
    _gpsUpdateTimer?.cancel();
    _gpsUpdateTimer = null;
  }

  Color _availabilityColor(String status) {
    switch (status) {
      case 'AVAILABLE':
        return Colors.green;
      case 'ENGAGED':
        return Colors.blue;
      case 'BUSY':
        return Colors.orange;
      case 'OFFLINE':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _acceptJob(Job job) async {
    try {
      await BookingApiService().acceptJob(job.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job accepted!'), backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept job: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _updateJobStatus(Job job, JobStatus newStatus) async {
    try {
      await BookingApiService().updateJobStatus(job.id, newStatus.toApiString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job updated to ${newStatus.label}'), backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update job: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markJobDone(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Done'),
        content: const Text('Are you sure you want to mark this job as done? The customer will be notified to review and approve.'),
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
      await BookingApiService().updateJobStatus(job.id, 'AWAITING_REVIEW');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job marked as done! Awaiting customer review.'), backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark job as done: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Color _statusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return Colors.orange;
      case JobStatus.adminApproved:
        return Colors.blue;
      case JobStatus.accepted:
        return Colors.indigo;
      case JobStatus.inProgress:
        return Colors.teal;
      case JobStatus.awaitingReview:
        return Colors.amber;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.cancelled:
        return Colors.red;
      case JobStatus.disputed:
        return Colors.pink;
      case JobStatus.rejected:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () => Navigator.pushNamed(context, '/wallet'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthApiService().logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: _isLoading
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
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Profile summary card
                        if (_artisanProfile != null) ...[
                          _buildProfileCard(),
                          const SizedBox(height: 12),
                          // Availability toggle card
                          _buildAvailabilityToggle(),
                          const SizedBox(height: 16),
                        ] else ...[
                          Card(
                            child: ListTile(
                              leading: Icon(Icons.person_add, color: Theme.of(context).primaryColor),
                              title: const Text('Create your artisan profile'),
                              subtitle: const Text('Set up your profession, skills, and rates'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                Navigator.pushNamed(context, '/profile');
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Jobs section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('My Jobs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('${_jobs.length} total', style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_jobs.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: Text('No jobs yet. Jobs will appear here when customers book you.')),
                            ),
                          )
                        else
                          ..._jobs.map((job) => _buildJobCard(job)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final a = _artisanProfile!;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _isUploadingPicture ? null : _showImageSourceDialog,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: a.profilePicture != null ? NetworkImage(a.profilePicture!) : null,
                    backgroundColor: Colors.grey.shade200,
                    child: a.profilePicture == null
                        ? Text(a.fullName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  if (_isUploadingPicture)
                    Positioned.fill(
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    ),
                  if (!_isUploadingPicture)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (a.profession != null) Text(a.profession!, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      Text(' ${a.rating.toStringAsFixed(1)} (${a.jobsCompleted} jobs)'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
              tooltip: 'Edit Profile',
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const EditArtisanProfileScreen()),
                );
                if (result == true) {
                  await _loadData();
                  if (mounted) {
                    context.read<ProfileViewModel>().fetchUserProfile();
                  }
                }
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.chat, color: Theme.of(context).primaryColor),
              onPressed: () => _navigateToConversations(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityToggle() {
    final currentStatus = _artisanProfile?.isAvailable ?? 'OFFLINE';
    final color = _availabilityColor(currentStatus);
    final isEngaged = currentStatus == 'ENGAGED';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radio_button_checked, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Availability: ${_availabilityLabel(currentStatus)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (_isTogglingAvailability) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            if (isEngaged) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your status is set to Engaged because you have an active booking. '
                        'You can switch to Busy or Offline.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'AVAILABLE',
                  label: Text('Available'),
                  icon: Icon(Icons.check_circle, size: 18),
                ),
                ButtonSegment(
                  value: 'BUSY',
                  label: Text('Busy'),
                  icon: Icon(Icons.work, size: 18),
                ),
                ButtonSegment(
                  value: 'OFFLINE',
                  label: Text('Offline'),
                  icon: Icon(Icons.visibility_off, size: 18),
                ),
              ],
              selected: {isEngaged ? 'BUSY' : currentStatus},
              onSelectionChanged: (selected) {
                if (isEngaged) {
                  final choice = selected.first;
                  if (choice == 'AVAILABLE') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cannot switch to Available while you have an active booking.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  _toggleAvailability(choice);
                } else {
                  _toggleAvailability(selected.first);
                }
              },
            ),
          ],
        ),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(job.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    job.status.label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 16, color: Colors.green),
                Text(' ${job.agreedPrice.toStringAsFixed(0)}'),
                const SizedBox(width: 16),
                if (job.location != null) ...[
                  const Icon(Icons.location_on, size: 16, color: Colors.red),
                  Text(' ${job.location!}', style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
            if (job.customerUsername != null) ...[
              const SizedBox(height: 4),
              Text('Customer: ${job.customerUsername}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            _buildJobActions(job),
          ],
        ),
      ),
    );
  }

  Widget _buildJobActions(Job job) {
    switch (job.status) {
      case JobStatus.adminApproved:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Accept Job'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () => _acceptJob(job),
              ),
            ),
          ],
        );
      case JobStatus.accepted:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Start Work'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _updateJobStatus(job, JobStatus.inProgress),
              ),
            ),
          ],
        );
      case JobStatus.inProgress:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle, size: 16),
              label: const Text('Mark as Done'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => _markJobDone(job),
            ),
          ],
        );
      case JobStatus.awaitingReview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Awaiting customer review. You will be notified once the customer approves.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case JobStatus.completed:
        if (job.escrowHeldAmount > 0) {
          return ElevatedButton.icon(
            icon: const Icon(Icons.payment, size: 16),
            label: const Text('View Escrow'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
              );
            },
          );
        }
        return const Text('Completed ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold));
      case JobStatus.rejected:
        return const Text('Rejected', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold));
      default:
        return const SizedBox.shrink();
    }
  }

  void _navigateToConversations() {
    Navigator.pushNamed(context, '/conversations');
  }
}