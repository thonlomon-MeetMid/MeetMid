import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/member.dart';
import '../../data/models/transport_mode.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import 'invite_bottom_sheet.dart';
import 'kick_confirm_dialog.dart';
import 'transfer_host_dialog.dart';

class RoomDetailScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roomListProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere((r) => r.id == widget.roomId, orElse: () => rooms.first);
    final currentUserName = ref.watch(authProvider).user?.name ?? '';
    final isHost = room.hostId.isNotEmpty && room.hostId == currentUserName;

    return Scaffold(
      appBar: AppHeader(
        title: room.name,
        action: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => InviteBottomSheet(roomId: widget.roomId),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text('초대',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _section(
                  '참여자 정보',
                  room.members
                      .map((m) => _memberTile(context, ref, m,
                          isCurrentUserHost: isHost,
                          hostId: room.hostId,
                          currentUserName: currentUserName))
                      .toList(),
                ),
                const Divider(height: 1, color: AppColors.border),
                _section('이동 수단',
                    room.members.map((m) => _transportTile(m)).toList()),
                const Divider(height: 1, color: AppColors.border),
                _section('소요 시간',
                    room.members.map((m) => _timeTile(m)).toList()),
              ],
            ),
          ),
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
                    onPressed: () =>
                        context.push('/room/${widget.roomId}/search-settings'),
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
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    WidgetRef ref,
    Member m, {
    required bool isCurrentUserHost,
    required String hostId,
    required String currentUserName,
  }) {
    final isMemberHost = m.name == hostId;
    // 본인 자신은 강퇴/양도 대상에서 제외
    final canActOn = isCurrentUserHost && m.name != currentUserName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onLongPress: canActOn
            ? () => _showMemberActionSheet(context, ref, m)
            : null,
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
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            // 이름 + 👑 배지
            Expanded(
              child: Row(
                children: [
                  Text(m.name,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textDark)),
                  if (isMemberHost) ...[
                    const SizedBox(width: 4),
                    const Text('👑', style: TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: () => context
                  .push('/room/${widget.roomId}/departure/${m.id}'),
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

  void _showMemberActionSheet(BuildContext context, WidgetRef ref, Member m) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(m.name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_remove, color: AppColors.error),
              title: const Text('강퇴하기',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => KickConfirmDialog(
                    memberName: m.name,
                    onConfirm: () => _kickMember(ref, m.name),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Text('👑', style: TextStyle(fontSize: 20)),
              title: const Text('방장 넘기기',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => TransferHostDialog(
                    memberName: m.name,
                    onConfirm: () => _transferHost(ref, m.name),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('취소',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _kickMember(WidgetRef ref, String targetName) async {
    final currentUserName = ref.read(authProvider).user?.name ?? '';
    final success = await ref.read(roomListProvider.notifier).kickMember(
          roomId: widget.roomId,
          requesterName: currentUserName,
          targetName: targetName,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '$targetName님을 강퇴했습니다' : '서버 오류 - 로컬에서만 제거됩니다'),
          backgroundColor: success ? null : Colors.orange,
        ),
      );
    }
  }

  Future<void> _transferHost(WidgetRef ref, String newHostName) async {
    final currentUserName = ref.read(authProvider).user?.name ?? '';
    final success = await ref.read(roomListProvider.notifier).transferHost(
          roomId: widget.roomId,
          requesterName: currentUserName,
          newHostName: newHostName,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? '$newHostName님이 방장이 되었습니다' : '서버 오류 - 로컬에만 반영됩니다'),
          backgroundColor: success ? null : Colors.orange,
        ),
      );
    }
  }

  Widget _transportTile(Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(_transportIcon(m.transport), size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(m.name,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textDark)),
          const Spacer(),
          Text(m.transport.label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _timeTile(Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(m.name,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textDark)),
          const Spacer(),
          Text('${m.travelMinutes ?? '-'}분',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  IconData _transportIcon(TransportMode mode) {
    switch (mode) {
      case TransportMode.transit:
        return Icons.directions_transit;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.walk:
        return Icons.directions_walk;
      case TransportMode.bike:
        return Icons.directions_bike;
    }
  }
}
