import '../models/place.dart';
import '../services/api_client.dart';

class PlaceRepository {
  final _api = ApiClient();

  Future<List<Place>> recommendPlaces({
    required String roomId,
    required String prompt,
    required double lat,
    required double lng,
    String category = '',
    int radius = 1000,
    int minRadius = 0,
    int size = 5,
  }) async {
    return _api.getPlaceRecommendations(
      roomId: roomId,
      prompt: prompt,
      lat: lat,
      lng: lng,
      category: category,
      radius: radius,
      minRadius: minRadius,
      size: size,
    );
  }
}