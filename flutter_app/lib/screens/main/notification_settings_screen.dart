import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/app_header.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _pushEnabled = true;
  bool _roomInviteEnabled = true;
  bool _midpointEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '알림 설정'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _switchItem(
            icon: Icons.notifications_outlined,
            title: '푸시 알림',
            subtitle: '모든 알림을 켜거나 끕니다',
            value: _pushEnabled,
            onChanged: (val) => setState(() => _pushEnabled = val),
          ),
          _switchItem(
            icon: Icons.group_add_outlined,
            title: '방 초대 알림',
            subtitle: '방에 초대됐을 때 알림을 받습니다',
            value: _roomInviteEnabled,
            onChanged: (val) => setState(() => _roomInviteEnabled = val),
          ),
          _switchItem(
            icon: Icons.place_outlined,
            title: '중간지점 알림',
            subtitle: '중간지점이 계산됐을 때 알림을 받습니다',
            value: _midpointEnabled,
            onChanged: (val) => setState(() => _midpointEnabled = val),
          ),
        ],
      ),
    );
  }

  Widget _switchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textDark)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}