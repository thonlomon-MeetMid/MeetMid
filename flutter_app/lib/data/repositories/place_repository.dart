import '../models/place.dart';
import '../services/api_client.dart';

class PlaceRepository {
  final ApiClient _apiClient;

  PlaceRepository(this._apiClient);

  /// Gemini AI를 통한 장소 추천 (Flask 백엔드 연동)
  Future<List<Place>> recommendPlaces(String query) async {
    try {
      final result = await _apiClient.recommendPlaces(query);
      return _parseRecommendation(result);
    } catch (_) {
      // 오프라인 또는 에러 시 더미 데이터 반환
      return _dummyPlaces();
    }
  }

  List<Place> _parseRecommendation(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final places = <Place>[];

    for (int i = 0; i < lines.length && i < 3; i++) {
      final line = lines[i].replaceFirst(RegExp(r'^\d+\.\s*'), '');
      final parts = line.split(' - ');
      final name = parts.isNotEmpty ? parts[0].trim() : '추천 장소 ${i + 1}';
      final desc = parts.length > 1 ? parts[1].trim() : '';

      places.add(Place(
        id: '${i + 1}',
        name: name,
        category: '카페',
        distance: '${(i + 1) * 300}m',
        address: desc,
        rating: 4.0 + (i * 0.3),
        aiRecommended: true,
      ));
    }

    return places;
  }

  List<Place> _dummyPlaces() => [
        const Place(
          id: '1',
          name: '블루보틀 강남점',
          category: '카페',
          distance: '350m',
          address: '서울 강남구 역삼동 123',
          rating: 4.5,
          aiRecommended: true,
        ),
        const Place(
          id: '2',
          name: '스타벅스 강남R점',
          category: '카페',
          distance: '500m',
          address: '서울 강남구 역삼동 456',
          rating: 4.2,
          aiRecommended: false,
        ),
        const Place(
          id: '3',
          name: '투썸플레이스 강남역점',
          category: '카페',
          distance: '800m',
          address: '서울 강남구 역삼동 789',
          rating: 4.0,
          aiRecommended: false,
        ),
      ];
}
