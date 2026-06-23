// lib/viewmodels/home_view_model.dart
import '../models/artisan.dart';
import '../models/job.dart';
import '../services/artisan_api_service.dart';
import '../services/booking_api_service.dart';
import 'base_view_model.dart';

class HomeViewModel extends BaseViewModel {
  final ArtisanApiService _artisanService = ArtisanApiService();
  final BookingApiService _bookingService = BookingApiService();

  List<Artisan> _featuredArtisans = [];
  List<Artisan> get featuredArtisans => _featuredArtisans;

  List<Job> _recentJobs = [];
  List<Job> get recentJobs => _recentJobs;

  Future<void> fetchData() async {
    setState(ViewState.loading);
    try {
      _featuredArtisans = await _artisanService.listArtisans(
        ordering: '-rating',
      );
      _recentJobs = await _bookingService.listJobs();
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }
}