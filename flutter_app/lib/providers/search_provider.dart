import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/search_criteria.dart';

final searchCriteriaProvider = StateProvider<SearchCriteria>(
  (ref) => SearchCriteria.timeFair,
);

final selectedPlaceIdProvider = StateProvider<String?>((ref) => null);
