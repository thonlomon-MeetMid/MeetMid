// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
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
  // null = 프롬프트 기반 AI 추천, non-null = 선택된 키워드
  String? _selectedKeyword;
  int _radius = 1000;
  String? _selectedPlaceId;

  static const _radiusOptions = [500, 1000, 3000, 5000];
  static const _radiusLabels = ['500m', '1km', '3km', '5km'];

  static const _suggestedKeywords = [
    '카페', '음식점', '술집', '편의점', '공원', '영화관', '노래방',
  ];

  // 카카오맵 카테고리 코드 매핑 (코드 있으면 키워드 검색 대신 카테고리 검색)
  static const _keywordToCategory = {
    '카페': 'CE7',
    '음식점': 'FD6',
    '편의점': 'CS2',
    '공원': 'AT4',
    '영화관': 'CT1',
  };

  // 반경 단계별 최소 거리 (이전 단계 결과 중복 제거)
  static const _radiusMinMap = {
    500: 0,
    1000: 500,
    3000: 1000,
    5000: 3000,
  };

  @override
  void initState() {
    super.initState();
    // 프롬프트 없으면 첫 번째 키워드(카페) 기본 선택
    final prompt = ref.read(searchPromptProvider);
    if (prompt.isEmpty) {
      _selectedKeyword = _suggestedKeywords.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = ref.watch(searchPromptProvider);
    final geminiKeyword = ref.read(geminiKeywordProvider);
    final midLat = ref.read(midpointLatProvider);
    final midLng = ref.read(midpointLngProvider);

    // geminiKeyword 우선, 없으면 기본 키워드(카페) — 원문 프롬프트를 카카오에 직접 보내지 않음
    final effectiveKeyword = _selectedKeyword ??
        (geminiKeyword.isNotEmpty ? geminiKeyword : _suggestedKeywords.first);

    // 선택된 키워드 또는 effectiveKeyword에 카테고리 코드가 있으면 카테고리 검색 사용
    final categoryCode = _keywordToCategory[effectiveKeyword] ?? '';

    final query = PlaceQuery(
      roomId: widget.roomId,
      keyword: effectiveKeyword,
      lat: midLat,
      lng: midLng,
      category: categoryCode,
      radius: _radius,
      minRadius: _radiusMinMap[_radius] ?? 0,
    );
    final placesAsync = ref.watch(placeRecommendProvider(query));

    return Scaffold(
      appBar: const AppHeader(title: '주변 장소 추천'),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),

          // ── AI 배너 (프롬프트 있을 때만) ──
          if (prompt.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: AppColors.aiPurpleLight,
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: AppColors.aiPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$prompt" 기반 장소를 찾고 있어요',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.aiPurpleDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── 키워드 칩 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // AI 추천 칩 (프롬프트 있을 때만)
                  if (prompt.isNotEmpty) ...[
                    _KeywordChip(
                      label: 'AI 추천',
                      icon: Icons.auto_awesome,
                      selected: _selectedKeyword == null,
                      isAi: true,
                      onTap: () => setState(() => _selectedKeyword = null),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 일반 키워드 칩들
                  ..._suggestedKeywords.map((kw) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _KeywordChip(
                          label: kw,
                          selected: _selectedKeyword == kw,
                          onTap: () =>
                              setState(() => _selectedKeyword = kw),
                        ),
                      )),
                ],
              ),
            ),
          ),

          // ── 반경 필터 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
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

          // ── 현재 검색 키워드 표시 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedKeyword == null && prompt.isNotEmpty
                    ? '"$prompt" 검색 결과'
                    : '"${_selectedKeyword ?? '전체'}" 검색 결과',
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
                            '근처에 해당 장소가 없어요\n반경을 늘리거나 다른 키워드를 선택해보세요',
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
                        final places =
                            ref.read(placeRecommendProvider(query)).valueOrNull ?? [];
                        final selected = places.where((p) => p.id == _selectedPlaceId).toList();
                        if (selected.isNotEmpty) {
                          ref.read(selectedPlaceProvider.notifier).state = selected.first;
                        }
                        ref.read(selectedPlaceIdProvider.notifier).state = _selectedPlaceId;
                        context.pop();
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
      onTap: () {
        setState(() => _selectedPlaceId = place.id);
        try {
          js.context.callMethod('flutterMoveMap', [place.lat, place.lng, 4]);
          js.context.callMethod('flutterMoveMidpointMarker', [place.lat, place.lng, place.name]);
        } catch (_) {}
      },
      child: Container(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.place,
                color: AppColors.textHint,
                size: 22,
              ),
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
                        const Icon(Icons.star, size: 11, color: Color(0xFFFFC107)),
                        const SizedBox(width: 2),
                        Text(
                          '${place.rating.toStringAsFixed(1)}${place.reviewCount > 0 ? ' (${place.reviewCount})' : ''}',
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

class _KeywordChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool isAi;
  final VoidCallback onTap;

  const _KeywordChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.isAi = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isAi && selected
        ? AppColors.aiPurple
        : selected
            ? AppColors.primary
            : AppColors.backgroundLight;
    final fg = selected ? Colors.white : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}
