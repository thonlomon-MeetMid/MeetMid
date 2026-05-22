import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/place.dart';
import '../data/repositories/place_repository.dart';
import '../data/services/api_client.dart';

final apiClientProvider = Provider((ref) => ApiClient());
final placeRepositoryProvider = Provider((ref) => PlaceRepository());

// /midpoint 응답에서 받은 Gemini 카테고리/키워드 저장
// → /places 호출 시 재사용 (Gemini 중복 호출 방지)
final geminiCategoryProvider = StateProvider<String>((ref) => '');
final geminiKeywordProvider = StateProvider<String>((ref) => '');

// 중간지점 좌표 저장 (place_recommend_screen에서 재사용)
final midpointLatProvider = StateProvider<double>((ref) => 0.0);
final midpointLngProvider = StateProvider<double>((ref) => 0.0);

class PlaceQuery {
  final String roomId;
  final String keyword;
  final double lat;
  final double lng;
  final String category;
  final int radius;

  const PlaceQuery({
    required this.roomId,
    required this.keyword,
    required this.lat,
    required this.lng,
    this.category = '',
    this.radius = 1000,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceQuery &&
          roomId == other.roomId &&
          keyword == other.keyword &&
          lat == other.lat &&
          lng == other.lng &&
          category == other.category &&
          radius == other.radius;

  @override
  int get hashCode =>
      roomId.hashCode ^
      keyword.hashCode ^
      lat.hashCode ^
      lng.hashCode ^
      category.hashCode ^
      radius.hashCode;
}

final placeRecommendProvider =
    FutureProvider.family<List<Place>, PlaceQuery>((ref, q) async {
  final repo = ref.read(placeRepositoryProvider);
  return repo.recommendPlaces(
    roomId: q.roomId,
    prompt: q.keyword,
    lat: q.lat,
    lng: q.lng,
    category: q.category,
    radius: q.radius,
  );
});