import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/place.dart';
import '../../providers/place_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class PlaceRecommendScreen extends ConsumerStatefulWidget {
  final String roomId;
  const PlaceRecommendScreen({super.key, required this.roomId});

  @override
  ConsumerState<PlaceRecommendScreen> createState() => _PlaceRecommendScreenState();
}

class _PlaceRecommendScreenState extends ConsumerState<PlaceRecommendScreen> {
  String _category = '카페';
  String _distance = '1km';
  String? _selectedPlaceId;

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(placeRecommendProvider('강남역 근처 $_category'));

    return Scaffold(
      appBar: const AppHeader(title: '주변 장소 추천'),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),

          // AI 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppColors.aiPurpleLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 분석 결과', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.aiPurple)),
                const SizedBox(height: 4),
                Text('"소개팅인데 분위기 카페 추천 좀"', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.aiPurpleDark)),
                const SizedBox(height: 2),
                Text('→ 분위기 좋은 카페 위주로 추천합니다', style: TextStyle(fontSize: 12, color: AppColors.aiPurpleText)),
              ],
            ),
          ),

          // 카테고리 탭
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: ['카페', '맛집', '술집'].map((c) {
                final selected = _category == c;
                return GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        Text(
                          c,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? AppColors.primary : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(height: 2, width: 30, color: selected ? AppColors.primary : Colors.transparent),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 거리 필터
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['500m', '1km', '1.5km', '2km', '3km'].map((d) {
                final selected = _distance == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _distance = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          const Divider(height: 1, color: AppColors.border),

          // 장소 리스트
          Expanded(
            child: placesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('장소를 불러올 수 없습니다')),
              data: (places) => ListView.separated(
                itemCount: places.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                itemBuilder: (_, i) => _placeTile(places[i]),
              ),
            ),
          ),

          // 하단 버튼
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppButton(
              text: '장소 선택 완료',
              onPressed: _selectedPlaceId != null
                  ? () {
                      ref.read(selectedPlaceIdProvider.notifier).state = _selectedPlaceId;
                      context.push('/room/${widget.roomId}/share');
                    }
                  : null,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                place.aiRecommended ? Icons.auto_awesome : Icons.place,
                color: place.aiRecommended ? AppColors.aiPurple : AppColors.textHint,
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
                      Text(place.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      if (place.aiRecommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.aiPurpleLight, borderRadius: BorderRadius.circular(4)),
                          child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.aiPurple)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${place.distance} · ${place.category}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Text('${place.rating}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(width: 2),
            const Icon(Icons.star, size: 14, color: Color(0xFFFBBF24)),
          ],
        ),
      ),
    );
  }
}
