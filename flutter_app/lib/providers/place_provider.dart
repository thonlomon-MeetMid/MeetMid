import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/place.dart';
import '../data/repositories/place_repository.dart';
import '../data/services/api_client.dart';

final apiClientProvider = Provider((ref) => ApiClient());

final placeRepositoryProvider = Provider((ref) => PlaceRepository());

final placeRecommendProvider =
    FutureProvider.family<List<Place>, String>((ref, query) async {
  final repo = ref.read(placeRepositoryProvider);
  return repo.recommendPlaces(query);
});
