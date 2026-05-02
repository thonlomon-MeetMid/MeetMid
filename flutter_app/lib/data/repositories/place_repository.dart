import '../models/place.dart';

class PlaceRepository {
  Future<List<Place>> recommendPlaces(String query) async {
    return _dummyPlaces();
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
