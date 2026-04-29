import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class SearchResultScreen extends ConsumerWidget {
  final String roomId;
  const SearchResultScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere((r) => r.id == roomId, orElse: () => rooms.first);

    return Scaffold(
      appBar: const AppHeader(title: '탐색 결과'),
      body: Column(
        children: [
          // 지도 영역 (도트 표시)
          Container(
            height: 280,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFBBDEFB), Color(0xFFC8E6C9)],
              ),
            ),
            child: Stack(
              children: [
                // 참여자 도트
                ..._buildDots(room.members.length),
                // 중심 도트
                Positioned(
                  left: 160,
                  top: 120,
                  child: Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),

          // 결과 정보
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 위치 정보
                  Row(
                    children: [
                      const Icon(Icons.place, size: 18, color: AppColors.primary),
                      const SizedBox(width: 4),
                      const Text('서울특별시 강남구', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 8),

                  const Text('중간지점: 강남역 부근', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  const Text('기준: 시간 공평', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 14),

                  const Text('참여자별 소요 시간', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),

                  ...room.members.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: AppColors.success,
                              child: Text(m.name[0], style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            Text(m.name, style: const TextStyle(fontSize: 14, color: AppColors.textDark)),
                            const Spacer(),
                            Text('${m.travelMinutes ?? '-'}분', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      )),

                  const Spacer(),

                  // 하단 버튼
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          text: '추천 장소',
                          variant: AppButtonVariant.outlined,
                          onPressed: () => context.push('/room/$roomId/recommend'),
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          text: '결과 공유',
                          onPressed: () => context.push('/room/$roomId/share'),
                          height: 48,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDots(int count) {
    final positions = [
      const Offset(60, 60),
      const Offset(260, 50),
      const Offset(40, 190),
      const Offset(280, 200),
      const Offset(150, 180),
    ];
    return List.generate(count > 5 ? 5 : count, (i) {
      return Positioned(
        left: positions[i].dx,
        top: positions[i].dy,
        child: Container(
          width: 14, height: 14,
          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
        ),
      );
    });
  }
}
