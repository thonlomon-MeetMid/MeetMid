import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/search_criteria.dart';

final searchCriteriaProvider = StateProvider<SearchCriteria>(
  (ref) => SearchCriteria.timeFair,
);

final selectedPlaceIdProvider = StateProvider<String?>((ref) => null);

// 탐색 프롬프트 (어디 가세요? 입력값)
final searchPromptProvider = StateProvider<String>((ref) => '');