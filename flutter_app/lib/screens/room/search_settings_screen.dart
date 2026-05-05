import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/search_criteria.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_header.dart';

class SearchSettingsScreen extends ConsumerStatefulWidget {
  final String roomId;
  const SearchSettingsScreen({super.key, required this.roomId});

  @override
  ConsumerState<SearchSettingsScreen> createState() =>
      _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends ConsumerState<SearchSettingsScreen> {
  final _geminiCtrl = TextEditingController();

  @override
  void dispose() {
    _geminiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(searchCriteriaProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AppHeader(title: '탐색 기준 설정'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 정보 배너 ──
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.infoBannerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '설정하면 방 전체에 공유됩니다',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── 탐색 기준 ──
                  const Text('탐색 기준',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark)),
                  const SizedBox(height: 12),

                  ...SearchCriteria.values.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () =>
                              ref.read(searchCriteriaProvider.notifier).state =
                                  c,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: selected == c
                                  ? AppColors.infoBannerBg
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected == c
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: selected == c ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected == c
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 20,
                                  color: selected == c
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c.label,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textDark)),
                                    Text(c.description,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppColors.textSecondary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),

                  // ── 구분선 ──
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: AppColors.border, height: 1),
                  ),

                  // ── 어디 가세요? (Gemini 더미) ──
                  Row(
                    children: [
                      const Text('어디 가세요?',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('선택',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _geminiCtrl,
                    maxLines: 2,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '예: 소개팅인데 분위기 카페 추천 좀',
                      hintStyle: const TextStyle(
                          fontSize: 14, color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.inputBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '자연어 입력 → Gemini AI가 맞춤 장소 추천',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),

          // ── 설정 완료 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.go('/room/${widget.roomId}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('설정 완료',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
