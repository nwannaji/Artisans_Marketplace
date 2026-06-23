// lib/screens/profile_screen.dart
import 'dart:io';
import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/models/user.dart';
import 'package:artisans_app/screens/account_settings_screen.dart';
import 'package:artisans_app/screens/booking_history_screen.dart';
import 'package:artisans_app/screens/chat_screen.dart';
import 'package:artisans_app/screens/edit_artisan_profile_screen.dart';
import 'package:artisans_app/screens/rating_selector.dart';
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/services/location_service.dart';
import 'package:artisans_app/viewmodels/base_view_model.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../viewmodels/profile_view_model.dart';

class ProfileScreen extends StatefulWidget {
  final int? artisanId; // If provided, show this artisan's public profile
  final Artisan? artisanData; // Pre-loaded artisan data (preserves distance from search)

  const ProfileScreen({super.key, this.artisanId, this.artisanData});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isDataFetched = false;
  Artisan? _viewedArtisan;
  bool _isLoadingArtisan = false;
  Job? _unratedJob; // The first completed-but-unrated job with this artisan
  bool _isCheckingJobs = false;

  @override
  void initState() {
    super.initState();
    // Use pre-loaded artisan data if available (preserves distance from search)
    _viewedArtisan = widget.artisanData;
    _isLoadingArtisan = widget.artisanData == null && widget.artisanId != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isDataFetched) {
      _isDataFetched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<ProfileViewModel>(context, listen: false).fetchUserProfile();
        if (widget.artisanId != null && widget.artisanData == null) {
          _loadArtisanProfile();
        }
        // Check for unrated completed jobs with this artisan
        if (widget.artisanId != null) {
          _checkForUnratedJobs();
        }
      });
    }
  }

  Future<void> _loadArtisanProfile() async {
    setState(() => _isLoadingArtisan = true);
    try {
      _viewedArtisan = await ArtisanApiService().getArtisanDetail(widget.artisanId!);
    } catch (e) {
      debugPrint('Error loading artisan profile: $e');
    }
    setState(() => _isLoadingArtisan = false);
  }

  /// Check if the current user has any completed-but-unrated jobs with this artisan.
  Future<void> _checkForUnratedJobs() async {
    setState(() => _isCheckingJobs = true);
    try {
      final jobs = await BookingApiService().listJobs(status: 'COMPLETED');
      // Find the first completed job with this artisan that hasn't been rated yet
      final unrated = jobs.where((j) =>
        j.artisanId == widget.artisanId && j.rating == null
      ).toList();
      if (unrated.isNotEmpty) {
        setState(() => _unratedJob = unrated.first);
      }
    } catch (e) {
      debugPrint('Error checking for unrated jobs: $e');
    }
    setState(() => _isCheckingJobs = false);
  }

  /// Show a rating dialog for the artisan.
  Future<void> _rateArtisan(Job job) async {
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
                Text('Rate ${_viewedArtisan?.fullName ?? "this artisan"}\'s work',
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating submitted! Thank you for your feedback.'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh the artisan profile to show updated rating
        await _loadArtisanProfile();
        setState(() => _unratedJob = null);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isViewingOther = widget.artisanId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isViewingOther ? 'Artisan Profile' : 'My Profile'),
      ),
      body: isViewingOther ? _buildArtisanProfile(context) : _buildOwnProfile(context),
    );
  }

  Widget _buildArtisanProfile(BuildContext context) {
    if (_isLoadingArtisan) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewedArtisan == null) {
      return const Center(child: Text('Could not load artisan profile.'));
    }
    final a = _viewedArtisan!;

    // Availability badge color
    Color availColor;
    String availLabel;
    switch (a.isAvailable) {
      case 'AVAILABLE':
        availColor = Colors.green;
        availLabel = 'Available';
        break;
      case 'ENGAGED':
        availColor = Colors.blue;
        availLabel = 'Engaged';
        break;
      case 'BUSY':
        availColor = Colors.orange;
        availLabel = 'Busy';
        break;
      default:
        availColor = Colors.grey;
        availLabel = 'Offline';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CircleAvatar(
            radius: 50,
            backgroundImage: a.profilePicture != null ? NetworkImage(a.profilePicture!) : null,
            child: a.profilePicture == null
                ? Text(a.fullName.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 24))
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(a.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        if (a.profession != null)
          Center(child: Text(a.profession!, style: const TextStyle(fontSize: 16, color: Colors.black54))),
        const SizedBox(height: 8),
        // Availability badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: availColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: availColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: availColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(availLabel, style: TextStyle(color: availColor, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: StarRatingDisplay(
            rating: a.rating,
            reviewCount: a.reviewCount,
            starSize: 20,
          ),
        ),
        // Rate this artisan (if user has an unrated completed job)
        if (_unratedJob != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rate ${a.fullName}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[800],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'You had a completed job with this artisan. Share your feedback!',
                  style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.star_border, size: 18),
                  label: const Text('Rate this artisan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _rateArtisan(_unratedJob!),
                ),
              ],
            ),
          ),
        ] else if (_isCheckingJobs) ...[
          const SizedBox(height: 8),
          const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
        if (a.jobsCompleted > 0)
          Center(
            child: Text(
              '${a.jobsCompleted} job${a.jobsCompleted != 1 ? "s" : ""} completed',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        if (a.distanceKm != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, color: Colors.blue, size: 16),
              Text(' ${a.distanceKm!.toStringAsFixed(1)} km away', style: const TextStyle(fontSize: 14)),
              if (a.estimatedArrivalMinutes != null)
                Text('  • ~${a.estimatedArrivalMinutes} min', style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ],
          ),
        ],
        if (a.location != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 16),
              Text(a.location!, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ],
        if (a.hourlyRate != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payment, color: Colors.green, size: 16),
              Text('${a.hourlyRate}/hr', style: const TextStyle(fontSize: 14)),
            ],
          ),
        ],
        if (a.bio != null && a.bio!.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('About', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(a.bio!),
        ],
        const SizedBox(height: 24),
        // Book this artisan button
        if (a.isAvailableNow)
          ElevatedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: const Text('Book this artisan'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _showBookingSheet(context, a),
          )
        else if (a.isEngaged)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: const Text('This artisan is currently engaged with a booking'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: Colors.blue,
              ),
              onPressed: null,
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_busy),
              label: Text('This artisan is $availLabel'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: availColor,
              ),
              onPressed: null,
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.chat),
          label: const Text('Message this artisan'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () async {
            final userId = await AuthApiService().getUserId();
            if (userId != null && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreenPage(
                    currentUserId: userId,
                    otherUserId: a.userId,
                    otherUserName: a.fullName,
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showBookingSheet(BuildContext context, Artisan artisan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BookingSheet(artisan: artisan),
    );
  }

  Widget _buildOwnProfile(BuildContext context) {
    return Consumer<ProfileViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.state == ViewState.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (viewModel.state == ViewState.error) {
          return Center(
            child: Text('Error loading profile: ${viewModel.errorMessage ?? "Unknown error"}'),
          );
        }
        if (viewModel.user == null) {
          return const Center(child: Text('User profile not found. Please log in again.'));
        }

        final user = viewModel.user!;
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _ProfileHeader(user: user),
            const SizedBox(height: 24),
            _ProfileOptionTile(
              icon: Icons.settings,
              title: 'Account Settings',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
                );
              },
            ),
            _ProfileOptionTile(
              icon: Icons.history,
              title: 'Booking History',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookingHistoryScreen()),
                );
              },
            ),
            if (user.role == UserRole.artisan)
              _ProfileOptionTile(
                icon: Icons.edit,
                title: 'Edit Profile',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditArtisanProfileScreen()),
                );
              },
            ),
            _ProfileOptionTile(
              icon: Icons.logout,
              title: 'Logout',
              textColor: Colors.red,
              onTap: () async {
                await viewModel.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (Route<dynamic> route) => false,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatefulWidget {
  final AppUser user;

  const _ProfileHeader({required this.user});

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _isUploadingPicture = false;

  Future<void> _pickAndUploadImage(ImageSource source) async {
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
      await context.read<ProfileViewModel>().fetchUserProfile();
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
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.user.photoUrl;

    return Column(
      children: [
        GestureDetector(
          onTap: _isUploadingPicture ? null : _showImageSourceDialog,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Icon(Icons.person_rounded, size: 60, color: Theme.of(context).colorScheme.primary)
                    : null,
              ),
              if (_isUploadingPicture)
                Positioned.fill(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  ),
                ),
              if (!_isUploadingPicture)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.user.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          widget.user.email,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Chip(
          label: Text(
            widget.user.role.name.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: Theme.of(context).primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ],
    );
  }
}

class _ProfileOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? textColor;

  const _ProfileOptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: textColor ?? Theme.of(context).iconTheme.color),
        title: Text(
          title,
          style: TextStyle(
            color: textColor ?? Theme.of(context).textTheme.titleMedium?.color,
            fontSize: 16,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

/// Bottom sheet for quick-booking an artisan
class _BookingSheet extends StatefulWidget {
  final Artisan artisan;
  const _BookingSheet({required this.artisan});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  DateTime? _scheduledTime;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null) return;
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _scheduledTime = DateTime(
        date.year, date.month, date.day,
        time.hour, time.minute,
      );
    });
  }

  Future<void> _submitBooking() async {
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what you need done');
      return;
    }
    if (_priceController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter an agreed price');
      return;
    }
    if (_scheduledTime == null) {
      setState(() => _error = 'Please select a date and time');
      return;
    }

    setState(() { _isSubmitting = true; _error = null; });

    try {
      // Try to get current location with address for the job
      double? lat, lng;
      String location = 'To be confirmed';
      try {
        final locationService = LocationService();
        final result = await locationService.getCurrentLocationWithAddress();
        if (result != null) {
          lat = result.latitude;
          lng = result.longitude;
          location = result.address;
        }
      } catch (_) {
        // Location not available, that's okay
      }

      final data = {
        'description': _descriptionController.text.trim(),
        'scheduled_time': _scheduledTime!.toIso8601String(),
        'agreed_price': double.parse(_priceController.text.trim()).toString(),
        'location': location.isNotEmpty ? location : 'To be confirmed',
        if (lat != null) 'latitude': lat.toStringAsFixed(6),
        if (lng != null) 'longitude': lng.toStringAsFixed(6),
      };

      await BookingApiService().createJobWithArtisan(data, widget.artisan.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking request sent! Awaiting admin approval.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // Close bottom sheet
    } catch (e) {
      if (!mounted) return;
      String errorMessage;
      if (e is ApiException) {
        errorMessage = e.fullMessage;
      } else {
        errorMessage = 'Booking failed. Please try again.';
      }
      setState(() {
        _isSubmitting = false;
        _error = errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artisan;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Artisan summary
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: a.profilePicture != null ? NetworkImage(a.profilePicture!) : null,
                child: a.profilePicture == null ? Text(a.fullName.substring(0, 1)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (a.profession != null)
                      Text(a.profession!, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              if (a.hourlyRate != null)
                Text('₦${a.hourlyRate!.toStringAsFixed(0)}/hr',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const Divider(height: 24),
          // Description
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What do you need done?',
              hintText: 'Describe the service you need...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          // Price
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Agreed price (₦)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.payment),
            ),
          ),
          const SizedBox(height: 12),
          // Date/Time picker
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(
              _scheduledTime != null
                  ? 'Scheduled: ${_scheduledTime!.day}/${_scheduledTime!.month}/${_scheduledTime!.year} at ${_scheduledTime!.hour}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                  : 'Select date and time',
            ),
            onPressed: _pickDateTime,
          ),
          const SizedBox(height: 16),
          // Error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          // Submit
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitBooking,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirm Booking', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}