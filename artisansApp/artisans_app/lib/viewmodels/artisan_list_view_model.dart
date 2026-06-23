// lib/viewmodels/artisan_list_view_model.dart
import '../models/artisan.dart';
import '../services/artisan_api_service.dart';
import 'base_view_model.dart';

class ArtisanListViewModel extends BaseViewModel {
  final ArtisanApiService _artisanService = ArtisanApiService();

  List<Artisan> _artisans = [];
  List<Artisan> get artisans => _artisans;

  Future<void> fetchArtisans() async {
    setState(ViewState.loading);
    try {
      _artisans = await _artisanService.listArtisans(ordering: '-rating');
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> searchArtisans(String query) async {
    setState(ViewState.loading);
    try {
      _artisans = await _artisanService.listArtisans(search: query);
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> fetchNearbyArtisans({
    required double lat,
    required double lng,
    double radiusKm = 2.0,
    String? profession,
  }) async {
    setState(ViewState.loading);
    try {
      _artisans = await _artisanService.getNearbyArtisans(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        profession: profession,
      );
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }
}