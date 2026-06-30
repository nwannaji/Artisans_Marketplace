import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/models/job.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/widgets/rating_selector.dart';
import 'package:artisans_app/screens/escrow_payment_screen.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/booking_api_service.dart';
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  List<Artisan> _nearbyArtisans = [];
  List<Artisan> _myArtisans = [];
  Map<int, Job?> _artisanLatestJob = {}; // artisanId -> latest job
  List<String> _professions = [];
  String? _selectedProfession;
  bool _isSearching = false;
  bool _isLoadingMyArtisans = false;
  String? _searchError;
  final searchController = TextEditingController();
  final Logger logger = Logger();
  final ArtisanApiService _artisanService = ArtisanApiService();
  final AuthApiService _authService = AuthApiService();
  final BookingApiService _bookingService = BookingApiService();
  final LocationService _locationService = LocationService();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializePage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _initializePage() async {
    await _getCurrentLocation();
    await _loadProfessions();
    _loadMyArtisans();
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await _locationService.getCurrentPosition();
    } catch (e) {
      logger.d("Location error: $e");
    }
  }

  Future<void> _loadProfessions() async {
    try {
      _professions = await _artisanService.fetchProfessions();
      setState(() {});
    } catch (e) {
      logger.d("Error loading professions: $e");
    }
  }

  Future<void> _loadMyArtisans() async {
    setState(() => _isLoadingMyArtisans = true);
    try {
      final jobs = await _bookingService.listJobs();
      // Group by artisanId, keeping the latest job per artisan (active first)
      final artisanJobMap = <int, Job>{};
      final order = <int>[]; // preserve first-seen order (latest jobs first from API)

      // Sort so active jobs come first
      final priority = <JobStatus, int>{
        JobStatus.awaitingReview: 0,
        JobStatus.inProgress: 1,
        JobStatus.accepted: 2,
        JobStatus.adminApproved: 3,
        JobStatus.completed: 4,
        JobStatus.pending: 5,
        JobStatus.disputed: 6,
        JobStatus.cancelled: 7,
        JobStatus.rejected: 8,
      };
      jobs.sort((a, b) => (priority[a.status] ?? 9).compareTo(priority[b.status] ?? 9));

      for (final job in jobs) {
        if (job.artisanId != null && !artisanJobMap.containsKey(job.artisanId)) {
          artisanJobMap[job.artisanId!] = job;
          order.add(job.artisanId!);
        }
      }

      // Fetch artisan details for each
      final artisans = <Artisan>[];
      final jobMap = <int, Job?>{};
      final failedIds = <int>[];
      for (final artisanId in order) {
        try {
          final artisan = await _artisanService.getArtisanDetail(artisanId);
          artisans.add(artisan);
          jobMap[artisanId] = artisanJobMap[artisanId];
        } catch (e) {
          logger.e("Error loading artisan $artisanId: $e");
          failedIds.add(artisanId);
        }
      }

      if (failedIds.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not load ${failedIds.length} artisan(s). They may have deactivated their account.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _myArtisans = artisans;
          _artisanLatestJob = jobMap;
          _isLoadingMyArtisans = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMyArtisans = false);
      }
    }
  }

  Future<void> _searchNearbyArtisans({String? profession, String? search}) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    final availability = (profession != null || search != null) ? 'all' : 'AVAILABLE';

    try {
      List<Artisan> results = [];

      if (_currentPosition != null) {
        // Progressive radius expansion: 10km → 25km → 50km
        for (double radius = 10.0; radius <= 50.0; radius += 15.0) {
          try {
            results = await _artisanService.getNearbyArtisans(
              lat: _currentPosition!.latitude,
              lng: _currentPosition!.longitude,
              radiusKm: radius,
              profession: profession,
              search: search,
              availability: availability,
            );
            if (results.isNotEmpty) break;
          } catch (e) {
            logger.d("Nearby search at ${radius}km failed: $e");
          }
        }

        if (results.isEmpty) {
          try {
            results = await _artisanService.listArtisans(
              profession: profession,
              search: search,
              ordering: '-rating',
              lat: _currentPosition!.latitude,
              lng: _currentPosition!.longitude,
            );
          } catch (e) {
            logger.d("Fallback list search failed: $e");
          }
        }
      } else {
        try {
          results = await _artisanService.listArtisans(
            profession: profession,
            search: search,
            ordering: '-rating',
          );
        } catch (e) {
          logger.d("Search without GPS failed: $e");
        }
      }

      setState(() {
        _nearbyArtisans = results;
        _isSearching = false;
        if (results.isEmpty) {
          final label = profession ?? search ?? 'artisan';
          _searchError = 'No $label found nearby. Try a different search.';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _navigateToProfile(Artisan artisan) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(artisanId: artisan.id, artisanData: artisan)),
    ).then((_) => _loadMyArtisans());
  }

  void _navigateToMap(Artisan artisan) {
    Navigator.pushNamed(context, '/artisan_map', arguments: {
      'artisan': artisan,
      'userLocation': _currentPosition != null
          ? {'latitude': _currentPosition!.latitude, 'longitude': _currentPosition!.longitude}
          : null,
    });
  }

  Future<void> _rateArtisan(Job job) async {
    final selectedRating = await showDialog<int>(
      context: context,
      builder: (context) => _RatingDialog(job: job),
    );
    if (selectedRating != null && selectedRating > 0 && mounted) {
      await _loadMyArtisans();
    }
  }

  Color _availabilityColor(String status) {
    switch (status) {
      case 'AVAILABLE': return Colors.green;
      case 'ENGAGED': return Colors.blue;
      case 'BUSY': return Colors.orange;
      case 'OFFLINE': return Colors.grey;
      default: return Colors.grey;
    }
  }

  /// Format distance for display: "Nearby" for <100m, meters for <1km, km otherwise.
  String _formatDistance(double km) {
    if (km < 0.1) return 'Nearby';
    if (km < 1.0) return '${(km * 1000).round()} m';
    if (km < 10.0) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  Color _statusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pending: return Colors.orange;
      case JobStatus.adminApproved: return Colors.blue;
      case JobStatus.accepted: return Colors.indigo;
      case JobStatus.inProgress: return Colors.teal;
      case JobStatus.awaitingReview: return Colors.amber;
      case JobStatus.completed: return Colors.green;
      case JobStatus.cancelled: return Colors.red;
      case JobStatus.disputed: return Colors.pink;
      case JobStatus.rejected: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Artisans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () => Navigator.pushNamed(context, '/wallet'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializePage,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Nearby'),
            Tab(icon: Icon(Icons.people), text: 'My Artisans'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          // Profession chips
          if (_professions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: _professions.map((profession) {
                  final isSelected = _selectedProfession == profession;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(profession),
                      selected: isSelected,
                      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      checkmarkColor: Theme.of(context).primaryColor,
                      onSelected: (selected) {
                        setState(() {
                          _selectedProfession = selected ? profession : null;
                          searchController.clear();
                        });
                        if (selected) {
                          _searchNearbyArtisans(profession: profession);
                        } else {
                          setState(() {
                            _nearbyArtisans = [];
                            _searchError = null;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNearbyTab(),
                _buildMyArtisansTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search by profession...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  setState(() => _selectedProfession = null);
                  _searchNearbyArtisans(search: value);
                }
              },
            ),
          ),
          if (searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                searchController.clear();
                setState(() {
                  _selectedProfession = null;
                  _nearbyArtisans = [];
                  _searchError = null;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNearbyTab() {
    if (_isSearching) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Searching nearby artisans...'),
        ],
      ));
    }

    if (_searchError != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(_searchError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _searchNearbyArtisans(
              profession: _selectedProfession,
              search: searchController.text.isNotEmpty ? searchController.text : null,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ));
    }

    if (_nearbyArtisans.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.handyman, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Select a profession above\nor search to find artisans nearby',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ));
    }

    return RefreshIndicator(
      onRefresh: () => _searchNearbyArtisans(
        profession: _selectedProfession,
        search: searchController.text.isNotEmpty ? searchController.text : null,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _nearbyArtisans.length,
        itemBuilder: (context, index) => _buildNearbyArtisanCard(_nearbyArtisans[index]),
      ),
    );
  }

  Widget _buildMyArtisansTab() {
    if (_isLoadingMyArtisans) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your artisans...'),
        ],
      ));
    }

    if (_myArtisans.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'You haven\'t hired any artisans yet.\nBook an artisan to see them here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ));
    }

    return RefreshIndicator(
      onRefresh: _loadMyArtisans,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _myArtisans.length,
        itemBuilder: (context, index) => _buildMyArtisanCard(_myArtisans[index]),
      ),
    );
  }

  Widget _buildNearbyArtisanCard(Artisan artisan) {
    final availColor = _availabilityColor(artisan.isAvailable);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _navigateToProfile(artisan),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  // Avatar with availability indicator
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: artisan.profilePicture != null
                            ? NetworkImage(artisan.profilePicture!)
                            : null,
                        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        child: artisan.profilePicture == null
                            ? Text(
                                artisan.fullName.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: availColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                artisan.fullName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (artisan.isVerified)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified, size: 16, color: Colors.blue),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        if (artisan.profession != null)
                          Text(artisan.profession!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            Text(' ${artisan.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                            if (artisan.reviewCount > 0)
                              Text(' (${artisan.reviewCount})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (artisan.hourlyRate != null) ...[
                              const SizedBox(width: 8),
                              Text('₦${artisan.hourlyRate!.toStringAsFixed(0)}/hr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Distance / ETA
                  if (_currentPosition != null) ...[
                    Builder(builder: (context) {
                      final dist = artisan.computeDistanceKm(
                        _currentPosition!.latitude, _currentPosition!.longitude,
                      );
                      if (dist == null) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _formatDistance(dist),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor),
                            ),
                          ),
                          if (artisan.estimatedArrivalMinutes != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '~${artisan.estimatedArrivalMinutes} min',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
              // Action row
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (artisan.latitude != null && artisan.longitude != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('View on Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                        side: BorderSide(color: Theme.of(context).primaryColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _navigateToMap(artisan),
                    ),
                  const SizedBox(width: 8),
                  if (artisan.isAvailableNow)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: const Text('Book'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _navigateToProfile(artisan),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyArtisanCard(Artisan artisan) {
    final job = _artisanLatestJob[artisan.id];
    final availColor = _availabilityColor(artisan.isAvailable);
    final statusColor = job != null ? _statusColor(job.status) : Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Top row: avatar + info
            InkWell(
              onTap: () => _navigateToProfile(artisan),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: artisan.profilePicture != null
                            ? NetworkImage(artisan.profilePicture!)
                            : null,
                        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        child: artisan.profilePicture == null
                            ? Text(
                                artisan.fullName.substring(0, 1).toUpperCase(),
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: availColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(artisan.fullName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (artisan.isVerified)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified, size: 16, color: Colors.blue),
                              ),
                          ],
                        ),
                        if (artisan.profession != null)
                          Text(artisan.profession!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            Text(' ${artisan.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                            if (artisan.reviewCount > 0)
                              Text(' (${artisan.reviewCount})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Job status badge
                  if (job != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        job.status.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ),
                ],
              ),
            ),
            // Action buttons row
            if (job != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // View on Map
                  if (artisan.latitude != null && artisan.longitude != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _navigateToMap(artisan),
                    ),
                  const SizedBox(width: 6),
                  // Message
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: () => _navigateToChat(artisan),
                  ),
                  const SizedBox(width: 6),
                  // Context-sensitive action button
                  if (job.status == JobStatus.awaitingReview && job.escrowHeldAmount > 0)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Review & Pay'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                        ).then((_) => _loadMyArtisans());
                      },
                    )
                  else if (job.status == JobStatus.awaitingReview && job.escrowHeldAmount == 0)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _approveCompletion(job),
                    )
                  else if ((job.status == JobStatus.accepted || job.status == JobStatus.inProgress) && job.escrowHeldAmount == 0)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.payment, size: 16),
                      label: const Text('Fund Escrow'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                        ).then((_) => _loadMyArtisans());
                      },
                    )
                  else if (job.status == JobStatus.completed && job.rating == null && job.artisanId != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.star, size: 16),
                      label: const Text('Rate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _rateArtisan(job),
                    )
                  else if (job.status == JobStatus.completed && job.escrowHeldAmount > 0)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.payment, size: 16),
                      label: const Text('Pay'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EscrowPaymentScreen(jobId: job.id, agreedPrice: job.agreedPrice)),
                        ).then((_) => _loadMyArtisans());
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToChat(Artisan artisan) async {
    final userId = await AuthApiService().getUserId();
    if (!mounted || userId == null) return;
    Navigator.pushNamed(context, '/conversations');
  }

  Future<void> _approveCompletion(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Completion'),
        content: const Text('Are you satisfied with the work? Approve to mark this job as completed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await BookingApiService().updateJobStatus(job.id, 'COMPLETED');
      if (!mounted) return;

      final escrowReleased = response['escrow_released'] == true;
      final otpRequired = response['escrow_release_otp_required'] == true;

      if (otpRequired) {
        // Escrow requires OTP — navigate to EscrowPaymentScreen for OTP entry
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job approved! Payment requires OTP confirmation.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        final escrowResult = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => EscrowPaymentScreen(
              jobId: job.id,
              agreedPrice: job.agreedPrice,
              job: job,
            ),
          ),
        );
        if (!mounted) return;
        if (escrowResult == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment released to artisan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadMyArtisans();
        return;
      }

      // Prompt for rating after approval
      final rated = await _showRatingDialog(job);
      if (!mounted) return;
      String message = rated ? 'Job approved and rated!' : 'Job approved!';
      if (escrowReleased) {
        message = rated ? 'Job approved, rated, and payment released!' : 'Job approved! Payment released to artisan.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
      _loadMyArtisans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<bool> _showRatingDialog(Job job) async {
    int selectedRating = 0;
    final reviewController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Rate ${job.artisanUsername ?? "Artisan"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RatingSelector(
                initialRating: 0,
                onRatingSelected: (rating) => setState(() => selectedRating = rating.toInt()),
                starSize: 36,
                showLabel: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reviewController,
                decoration: const InputDecoration(
                  hintText: 'Write a review (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedRating == 0 ? null : () => Navigator.pop(context, {
                'rating': selectedRating.toDouble(),
                'review': reviewController.text,
              }),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        await BookingApiService().rateJob(job.id, result['rating'] as double, review: result['review'] as String?);
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rating failed. You can rate later from booking history.'), backgroundColor: Colors.orange),
          );
        }
        return false;
      }
    }
    return false;
  }
}

/// Standalone rating dialog widget
class _RatingDialog extends StatelessWidget {
  final Job job;
  const _RatingDialog({required this.job});

  @override
  Widget build(BuildContext context) {
    int selectedRating = 0;
    final reviewController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Rate ${job.artisanUsername ?? "Artisan"}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RatingSelector(
              initialRating: 0,
              onRatingSelected: (rating) => setState(() => selectedRating = rating.toInt()),
              starSize: 36,
              showLabel: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reviewController,
              decoration: const InputDecoration(
                hintText: 'Write a review (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: selectedRating == 0 ? null : () => Navigator.pop(context, selectedRating),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}