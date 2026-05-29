import '../models/place.dart';
import '../services/api_client.dart';

class PlaceRepository {
  final _api = ApiClient();

  Future<List<Place>> recommendPlaces({
    required String roomId,
    required String categoryCode,
    required double lat,
    required double lng,
    int radius = 500,
    int minRadius = 0,
    int size = 5,
  }) async {
    return _api.getPlaceRecommendations(
      roomId: roomId,
      categoryCode: categoryCode,
      lat: lat,
      lng: lng,
      radius: radius,
      minRadius: minRadius,
      size: size,
    );
  }
}
