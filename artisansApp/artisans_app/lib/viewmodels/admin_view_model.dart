// lib/viewmodels/admin_view_model.dart
import '../models/job.dart';
import '../models/artisan.dart';
import '../services/booking_api_service.dart';
import '../services/artisan_api_service.dart';
import 'base_view_model.dart';

class AdminViewModel extends BaseViewModel {
  final BookingApiService _bookingService = BookingApiService();
  final ArtisanApiService _artisanService = ArtisanApiService();

  List<Job> _pendingJobs = [];
  List<Job> get pendingJobs => _pendingJobs;

  List<Job> _allJobs = [];
  List<Job> get allJobs => _allJobs;

  List<Artisan> _artisans = [];
  List<Artisan> get artisans => _artisans;

  /// Load all jobs pending admin approval
  Future<void> loadPendingJobs() async {
    setState(ViewState.loading);
    try {
      _pendingJobs = await _bookingService.listJobs(status: 'PENDING');
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Load all jobs (for admin dashboard)
  Future<void> loadAllJobs() async {
    setState(ViewState.loading);
    try {
      _allJobs = await _bookingService.listJobs();
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Load all artisans
  Future<void> loadArtisans() async {
    setState(ViewState.loading);
    try {
      _artisans = await _artisanService.listArtisans();
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Approve a pending job
  Future<bool> approveJob(int jobId) async {
    try {
      await _bookingService.approveJob(jobId);
      // Remove from pending list
      _pendingJobs.removeWhere((j) => j.id == jobId);
      notifyListeners();
      return true;
    } catch (e) {
      setError(e.toString());
      return false;
    }
  }
}