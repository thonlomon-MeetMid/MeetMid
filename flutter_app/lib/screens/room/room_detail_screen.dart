import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/member.dart';
import '../../data/models/transport_mode.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import 'invite_bottom_sheet.dart';
import 'kick_confirm_dialog.dart';

class RoomDetailScreen extends ConsumerWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere((r) => r.id == roomId, orElse: () => rooms.first);

    return Scaffold(
      appBar: AppHeader(
        title: room.name,
        action: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => InviteBottomSheet(roomId: roomId),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text('초대', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 멤버 정보 섹션
          Expanded(
            child: ListView(
              children: [
                _section('참여자 정보', room.members.map((m) => _memberTile(context, ref, m)).toList()),
                const Divider(height: 1, color: AppColors.border),
                _section('이동 수단', room.members.map((m) => _transportTile(m)).toList()),
                const Divider(height: 1, color: AppColors.border),
                _section('소요 시간', room.members.map((m) => _timeTile(m)).toList()),
              ],
            ),
          ),

          // 하단 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: '카카오톡으로 공유',
                    variant: AppButtonVariant.kakao,
                    icon: Icons.chat_bubble,
                    height: 48,
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: '장소 공유',
                    onPressed: () => context.push('/room/$roomId/search-settings'),
                    height: 48,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, WidgetRef ref, Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onLongPress: () => showDialog(
          context: context,
          builder: (_) => KickConfirmDialog(
            memberName: m.name,
            onConfirm: () =>
                ref.read(roomListProvider.notifier).removeMember(roomId, m.id),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                m.name[0],
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                m.name,
                style: const TextStyle(fontSize: 14, color: AppColors.textDark),
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/room/$roomId/departure/${m.id}'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.departure.isEmpty ? '출발지 입력' : m.departure,
                    style: TextStyle(
                      fontSize: 13,
                      color: m.departure.isEmpty
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: m.departure.isEmpty
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.textHint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _transportTile(Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(_transportIcon(m.transport), size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(m.name, style: const TextStyle(fontSize: 14, color: AppColors.textDark)),
          const Spacer(),
          Text(m.transport.label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _timeTile(Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(m.name, style: const TextStyle(fontSize: 14, color: AppColors.textDark)),
          const Spacer(),
          Text('${m.travelMinutes ?? '-'}분', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  IconData _transportIcon(TransportMode mode) {
    switch (mode) {
      case TransportMode.transit: return Icons.directions_transit;
      case TransportMode.car: return Icons.directions_car;
      case TransportMode.walk: return Icons.directions_walk;
      case TransportMode.bike: return Icons.directions_bike;
    }
  }
}
