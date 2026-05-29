import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/place.dart';
import '../../providers/place_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_header.dart';

class PlaceRecommendScreen extends ConsumerStatefulWidget {
  final String roomId;
  const PlaceRecommendScreen({super.key, required this.roomId});

  @override
  ConsumerState<PlaceRecommendScreen> createState() =>
      _PlaceRecommendScreenState();
}

class _PlaceRecommendScreenState extends ConsumerState<PlaceRecommendScreen> {
  late String _selectedCategoryCode;
  int _radius = 500;
  String? _selectedPlaceId;

  static const _radiusOptions = [500, 1000, 3000, 5000];
  static const _radiusLabels = ['500m', '1km', '3km', '5km'];

  static const _radiusMinMap = {
    500: 0,
    1000: 500,
    3000: 1000,
    5000: 3000,
  };

  static const _categories = [
    ('', '전체'),
    ('FD6', '식당'),
    ('CE7', '카페'),
    ('CS2', '편의점'),
    ('CT1', '문화시설'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategoryCode = ref.read(selectedCategoryCodeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final midLat = ref.read(midpointLatProvider);
    final midLng = ref.read(midpointLngProvider);

    final query = PlaceQuery(
      roomId: widget.roomId,
      categoryCode: _selectedCategoryCode,
      lat: midLat,
      lng: midLng,
      radius: _radius,
      minRadius: _radiusMinMap[_radius] ?? 0,
    );
    final placesAsync = ref.watch(placeRecommendProvider(query));

    final categoryLabel = _categories
        .firstWhere((c) => c.$1 == _selectedCategoryCode,
            orElse: () => const ('', '전체'))
        .$2;

    return Scaffold(
      appBar: const AppHeader(title: '주변 장소 추천'),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),

          // ── 카테고리 칩 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((c) {
                  final isSelected = _selectedCategoryCode == c.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategoryCode = c.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.backgroundLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          c.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── 반경 필터 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 8),
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

          const Divider(height: 1, color: AppColors.border),

          // ── 현재 검색 표시 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '"$categoryLabel" 검색 결과',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          // ── 장소 리스트 ──
          Expanded(
            child: placesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('장소를 불러올 수 없습니다')),
              data: (places) => places.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text(
                            '근처에 해당 장소가 없어요\n반경을 늘리거나 다른 카테고리를 선택해보세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: places.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.border),
                      itemBuilder: (_, i) => _placeTile(places[i], query),
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
                        final places =
                            ref.read(placeRecommendProvider(query)).valueOrNull ?? [];
                        final found = places
                            .where((p) => p.id == _selectedPlaceId)
                            .toList();
                        if (found.isNotEmpty) {
                          final place = found.first;
                          ref.read(selectedPlaceProvider.notifier).state = place;
                          ref.read(selectedPlaceIdProvider.notifier).state =
                              _selectedPlaceId;
                          context.pop(<String, dynamic>{
                            'name': place.name,
                            'lat': place.lat,
                            'lng': place.lng,
                          });
                        } else {
                          context.pop();
                        }
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

  // 카테고리 코드 → (아이콘, 색상)
  static (IconData, Color) _categoryStyle(String code) => switch (code) {
        'FD6' => (Icons.restaurant, const Color(0xFFFF7043)),
        'CE7' => (Icons.local_cafe, const Color(0xFF795548)),
        'CS2' => (Icons.store, const Color(0xFF4CAF50)),
        'CT1' => (Icons.museum, const Color(0xFF9C27B0)),
        _ => (Icons.place, AppColors.primary),
      };

  Widget _placeTile(Place place, PlaceQuery query) {
    final selected = _selectedPlaceId == place.id;
    final (icon, iconColor) = _categoryStyle(_selectedCategoryCode);
    return GestureDetector(
      onTap: () => setState(() => _selectedPlaceId = place.id),
      child: Container(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${place.distance} · ${place.category}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (place.rating > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star,
                            size: 11, color: Color(0xFFFFC107)),
                        const SizedBox(width: 2),
                        Text(
                          '${place.rating.toStringAsFixed(1)}'
                          '${place.reviewCount > 0 ? ' (${place.reviewCount})' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  if (place.address.isNotEmpty)
                    Text(
                      place.address,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
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
