import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: const AppHeader(title: '설정'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 프로필 카드
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0] : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? '사용자', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(user?.email ?? '', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _settingsItem(Icons.notifications_outlined, '알림 설정'),
          _settingsItem(Icons.language, '언어 설정'),
          _settingsItem(Icons.info_outline, '앱 정보'),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/auth/login');
            },
            child: const Text('로그아웃', style: TextStyle(color: AppColors.error, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _settingsItem(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 15, color: AppColors.textDark)),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
        ],
      ),
    );
  }
}
