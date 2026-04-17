import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class ShareResultScreen extends ConsumerWidget {
  final String roomId;
  const ShareResultScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: const AppHeader(title: '결과 공유'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 결과 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 스터디 모임 레이블
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('스터디 모임', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 14),

                  const Text('강남역 부근', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  const Text('카페 존', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),

                  // 선택된 장소
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundGray,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.place, size: 20, color: AppColors.primary),
                        SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('블루보틀 강남점', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                            Text('350m · 카페', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 공유 방법 레이블
            const Text('공유 방법', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 12),

            // 카카오톡 공유
            AppButton(
              text: '카카오톡으로 공유',
              variant: AppButtonVariant.kakao,
              icon: Icons.chat_bubble,
              height: 52,
              onPressed: () {},
            ),
            const SizedBox(height: 10),

            // 링크 복사
            AppButton(
              text: '링크 복사',
              variant: AppButtonVariant.outlined,
              icon: Icons.link,
              onPressed: () {},
            ),
            const SizedBox(height: 10),

            // 개별 길안내
            AppButton(
              text: '개별 길안내',
              variant: AppButtonVariant.outlined,
              icon: Icons.directions,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
