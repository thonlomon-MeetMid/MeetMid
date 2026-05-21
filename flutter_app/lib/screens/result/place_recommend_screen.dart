import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/place.dart';
import '../../providers/place_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/place_provider.dart';
import '../../widgets/common/app_header.dart';

class PlaceRecommendScreen extends ConsumerStatefulWidget {
  final String roomId;
  const PlaceRecommendScreen({super.key, required this.roomId});

  @override
  ConsumerState<PlaceRecommendScreen> createState() =>
      _PlaceRecommendScreenState();
}

class _PlaceRecommendScreenState
    extends ConsumerState<PlaceRecommendScreen> {
  String _selectedCategory = '';
  int _radius = 1000;
  String? _selectedPlaceId;

  // 반경 옵션
  static const _radiusOptions = [500, 1000, 1500, 2000, 3000];
  static const _radiusLabels = ['500m', '1km', '1.5km', '2km', '3km'];

  // 카테고리 탭 옵션
  static const _categoryOptions = [
    {'label': '전체', 'code': ''},
    {'label': '카페', 'code': 'CE7'},
    {'label': '음식점', 'code': 'FD6'},
    {'label': '공원', 'code': 'AT4'},
    {'label': '영화관', 'code': 'CT1'},
  ];

  @override
  Widget build(BuildContext context) {
    final prompt = ref.watch(searchPromptProvider);
    final geminiCategory = ref.watch(geminiCategoryProvider);
    final geminiKeyword = ref.watch(geminiKeywordProvider);
    final midLat = ref.watch(midpointLatProvider);
    final midLng = ref.watch(midpointLngProvider);

    // 사용자가 탭 직접 선택 시 우선, 없으면 Gemini 결과 사용
    final effectiveCategory = _selectedCategory.isNotEmpty
        ? _selectedCategory
        : geminiCategory;
    final effectiveKeyword = geminiKeyword.isNotEmpty ? geminiKeyword : prompt;

    final query = PlaceQuery(
      roomId: widget.roomId,
      keyword: effectiveKeyword,
      lat: midLat,
      lng: midLng,
      category: effectiveCategory,
      radius: _radius,
    );
    final placesAsync = ref.watch(placeRecommendProvider(query));

    return Scaffold(
      appBar: const AppHeader(title: '주변 장소 추천'),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),

          // ── AI 배너 ──
          if (prompt.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.aiPurpleLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 분석 중',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.aiPurple)),
                  const SizedBox(height: 4),
                  Text('"$prompt"',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.aiPurpleDark)),
                  const SizedBox(height: 2),
                  Text('→ 중간지점 근처에서 맞춤 장소를 찾고 있어요',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.aiPurpleText)),
                ],
              ),
            ),

          // ── 카테고리 탭 ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categoryOptions.map((c) {
                  final selected = _selectedCategory == c['code'];
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategory = c['code']!),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          Text(
                            c['label']!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                              height: 2,
                              width: 30,
                              color: selected
                                  ? AppColors.primary
                                  : Colors.transparent),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── 반경 필터 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_radiusOptions.length, (i) {
                  final selected = _radius == _radiusOptions[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _radius = _radiusOptions[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.backgroundLight,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          _radiusLabels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),

          // ── 장소 리스트 ──
          Expanded(
            child: placesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('장소를 불러올 수 없습니다')),
              data: (places) => places.isEmpty
                  ? const Center(
                      child: Text('근처에 해당 장소가 없습니다',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary)))
                  : ListView.separated(
                      itemCount: places.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.border),
                      itemBuilder: (_, i) => _placeTile(places[i]),
                    ),
            ),
          ),

          // ── 하단 버튼 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _selectedPlaceId != null
                    ? () {
                        ref
                            .read(selectedPlaceIdProvider.notifier)
                            .state = _selectedPlaceId;
                        context.push('/room/${widget.roomId}/share');
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('장소 선택 완료',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeTile(Place place) {
    final selected = _selectedPlaceId == place.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlaceId = place.id),
      child: Container(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                place.aiRecommended
                    ? Icons.auto_awesome
                    : Icons.place,
                color: place.aiRecommended
                    ? AppColors.aiPurple
                    : AppColors.textHint,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(place.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark)),
                      ),
                      if (place.aiRecommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.aiPurpleLight,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('AI',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.aiPurple)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${place.distance} · ${place.category}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                  ),
                  if (place.address.isNotEmpty)
                    Text(
                      place.address,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}