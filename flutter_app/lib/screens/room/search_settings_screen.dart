import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/search_criteria.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class SearchSettingsScreen extends ConsumerWidget {
  final String roomId;
  const SearchSettingsScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(searchCriteriaProvider);

    return Scaffold(
      appBar: const AppHeader(title: '탐색 기준 설정'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 정보 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.infoBannerBg,
              child: Row(
                children: [
                  const Icon(Icons.info, size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('설정하면 방 전체에 공유됩니다', style: TextStyle(fontSize: 13, color: AppColors.infoBannerText)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text('탐색 기준', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: 12),

            // 라디오 옵션
            ...SearchCriteria.values.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => ref.read(searchCriteriaProvider.notifier).state = c,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected == c ? AppColors.infoBannerBg : AppColors.inputBackgroundAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected == c ? AppColors.primary : AppColors.border,
                          width: selected == c ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected == c ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 20,
                            color: selected == c ? AppColors.primary : AppColors.textHint,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                                Text(c.description, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),

            // 목적지 섹션
            const SizedBox(height: 16),
            const Text('목적지', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.inputBackgroundAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, size: 18, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  const Text('목적지 없음 (자동 탐색)', style: TextStyle(fontSize: 14, color: AppColors.textHint)),
                ],
              ),
            ),

            const Spacer(),

            AppButton(
              text: '설정 완료',
              onPressed: () => context.push('/room/$roomId/search-result'),
            ),
          ],
        ),
      ),
    );
  }
}
