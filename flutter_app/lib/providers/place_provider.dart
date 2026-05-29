import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/place.dart';
import '../data/repositories/place_repository.dart';
import '../data/services/api_client.dart';

final apiClientProvider = Provider((ref) => ApiClient());
final placeRepositoryProvider = Provider((ref) => PlaceRepository());

// 중간지점 좌표 + 주소 저장
final midpointLatProvider = StateProvider<double>((ref) => 0.0);
final midpointLngProvider = StateProvider<double>((ref) => 0.0);
final midpointAddressProvider = StateProvider<String>((ref) => '');

// 장소 확정 시 선택된 Place 전체 저장
final selectedPlaceProvider = StateProvider<Place?>((ref) => null);

// 카테고리 선택 저장 ('' = 전체, 'FD6' = 식당, 'CE7' = 카페, 등)
final selectedCategoryCodeProvider = StateProvider<String>((ref) => '');

// 공유 화면 닫힐 때 결과 화면 지도 뷰포트 재적용 신호
final mapViewportTickProvider = StateProvider<int>((ref) => 0);

class PlaceQuery {
  final String roomId;
  final String categoryCode;
  final double lat;
  final double lng;
  final int radius;
  final int minRadius;

  const PlaceQuery({
    required this.roomId,
    required this.categoryCode,
    required this.lat,
    required this.lng,
    this.radius = 500,
    this.minRadius = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceQuery &&
          roomId == other.roomId &&
          categoryCode == other.categoryCode &&
          lat == other.lat &&
          lng == other.lng &&
          radius == other.radius &&
          minRadius == other.minRadius;

  @override
  int get hashCode =>
      roomId.hashCode ^
      categoryCode.hashCode ^
      lat.hashCode ^
      lng.hashCode ^
      radius.hashCode ^
      minRadius.hashCode;
}

final placeRecommendProvider =
    FutureProvider.family<List<Place>, PlaceQuery>((ref, q) async {
  final repo = ref.read(placeRepositoryProvider);
  return repo.recommendPlaces(
    roomId: q.roomId,
    categoryCode: q.categoryCode,
    lat: q.lat,
    lng: q.lng,
    radius: q.radius,
    minRadius: q.minRadius,
  );
});
