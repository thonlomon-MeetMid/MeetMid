import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/place_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class ShareResultScreen extends ConsumerWidget {
  final String roomId;
  const ShareResultScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPlace = ref.watch(selectedPlaceProvider);
    final midAddress = ref.watch(midpointAddressProvider);
    final rooms = ref.watch(roomListProvider).valueOrNull ?? [];
    final roomMatches = rooms.where((r) => r.id == roomId);
    final roomName = roomMatches.isNotEmpty ? roomMatches.first.name : '모임';

    final destinationName = selectedPlace != null
        ? selectedPlace.name
        : (midAddress.isNotEmpty ? midAddress : '중간 지점');

    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: const AppHeader(title: '결과 공유'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    destinationName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedPlace != null ? '선택된 장소' : '중간 지점',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (selectedPlace != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundGray,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place, size: 20, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedPlace.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  '${selectedPlace.distance} · ${selectedPlace.category}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (selectedPlace.address.isNotEmpty)
                                  Text(
                                    selectedPlace.address,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textHint,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              '공유 방법',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),

            AppButton(
              text: '카카오톡으로 공유',
              variant: AppButtonVariant.kakao,
              icon: Icons.chat_bubble,
              height: 52,
              onPressed: () {},
            ),
            const SizedBox(height: 10),

            AppButton(
              text: '링크 복사',
              variant: AppButtonVariant.outlined,
              icon: Icons.link,
              onPressed: () {},
            ),
            const SizedBox(height: 10),

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
