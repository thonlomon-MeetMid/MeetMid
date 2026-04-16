import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class KickConfirmDialog extends StatelessWidget {
  final String memberName;
  final VoidCallback onConfirm;

  const KickConfirmDialog({
    super.key,
    required this.memberName,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 빨간 아이콘
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_remove, color: AppColors.error, size: 28),
            ),
            const SizedBox(height: 16),

            Text(
              '$memberName님을 강퇴할까요?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '강퇴하면 이 방에 다시 참여할 수 없습니다',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(0, 46),
                    ),
                    child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      onConfirm();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(0, 46),
                    ),
                    child: const Text('강퇴'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
