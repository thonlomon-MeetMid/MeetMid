import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/app_header.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '앱 정보'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 앱 로고 및 이름
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: const Icon(Icons.place,
                      size: 40, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                const Text('MeetMid',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark)),
                const SizedBox(height: 4),
                const Text('버전 1.0.0',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 앱 정보 항목들 (나중에 내용 채울 부분)
          _infoItem('만든 사람', '추후 작성'),
          _infoItem('문의', '추후 작성'),
          _infoItem('개인정보처리방침', '추후 작성'),
          _infoItem('서비스 이용약관', '추후 작성'),
        ],
      ),
    );
  }

  Widget _infoItem(String title, String value) {
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
          Text(title,
              style: const TextStyle(fontSize: 15, color: AppColors.textDark)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}