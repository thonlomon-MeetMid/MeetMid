import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/member.dart';
import '../../data/models/room.dart';
import '../../data/models/transport_mode.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/search_provider.dart';
import '../../data/models/search_criteria.dart';
import '../../widgets/common/app_header.dart';
import 'add_member_dialog.dart';
import 'edit_member_dialog.dart';
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
  Timer? _pollTimer;
  bool _isLocating = false;
  final _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roomListProvider.notifier).refresh();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.read(roomListProvider.notifier).silentRefresh();
      _checkSearchStatus();
    });
  }

  Future<void> _checkSearchStatus() async {
    final rooms = ref.read(roomListProvider).valueOrNull ?? [];
    if (rooms.isEmpty) return;
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final currentUserName = ref.read(authProvider).user?.name ?? '';
    // 방장은 폴링 안 함
    if (room.hostId == currentUserName) return;

    final status = await _apiClient.getSearchStatus(widget.roomId);
    if (status['started'] == true && mounted) {
      _pollTimer?.cancel();
      final criteria = status['criteria'] as String? ?? 'distanceFair';
      final criteriaEnum = SearchCriteria.values.firstWhere(
        (e) => e.name == criteria,
        orElse: () => SearchCriteria.distanceFair,
      );
      ref.read(searchCriteriaProvider.notifier).state = criteriaEnum;
      context.push('/room/${widget.roomId}/search-result');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 헬퍼 ──────────────────────────────────────────────────

  Member? _findMyMember(List<Member> members, String userName) {
    try {
      return members.firstWhere((m) => m.name == userName);
    } catch (_) {
      return null;
    }
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

  // ── 액션 ──────────────────────────────────────────────────

  Future<void> _setCurrentLocation(Member? myMember) async {
    if (myMember == null) return;
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 거부되었습니다');
      }
      final position = await Geolocator.getCurrentPosition();
      final address = await _apiClient.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (address.isEmpty) throw Exception('주소를 가져올 수 없습니다');
      if (!mounted) return;
      final user = ref.read(authProvider).user;
      await ref
          .read(roomListProvider.notifier)
          .updateMemberTransport(
            roomId: widget.roomId,
            memberName: user?.name ?? '',
            address: address,
            transport: myMember.transport,
            userUuid: user?.id ?? '',
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _selectTransport(
    Member myMember,
    TransportMode transport,
  ) async {
    final user = ref.read(authProvider).user;
    await ref
        .read(roomListProvider.notifier)
        .updateMemberTransport(
          roomId: widget.roomId,
          memberName: myMember.name,
          address: myMember.departure,
          transport: transport,
          userUuid: user?.id ?? '',
        );
  }

  Future<void> _kickMember(String targetName) async {
    final currentUserName = ref.read(authProvider).user?.name ?? '';
    final success = await ref
        .read(roomListProvider.notifier)
        .kickMember(
          roomId: widget.roomId,
          requesterName: currentUserName,
          targetName: targetName,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '$targetName님을 강퇴했습니다' : '강퇴에 실패했습니다'),
          backgroundColor: success ? null : Colors.orange,
        ),
      );
    }
  }

  Future<void> _transferHost(String newHostName) async {
    final currentUserName = ref.read(authProvider).user?.name ?? '';
    final success = await ref
        .read(roomListProvider.notifier)
        .transferHost(
          roomId: widget.roomId,
          requesterName: currentUserName,
          newHostName: newHostName,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '$newHostName님이 방장이 되었습니다' : '방장 이전에 실패했습니다'),
          backgroundColor: success ? null : Colors.orange,
        ),
      );
    }
  }

  Future<void> _leaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방 나가기'),
        content: const Text('정말 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final userName = ref.read(authProvider).user?.name ?? '';
    final success = await ref
        .read(roomListProvider.notifier)
        .leaveRoom(roomId: widget.roomId, userName: userName);
    if (!mounted) return;
    if (success) {
      context.go('/map');
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('방 나가기에 실패했습니다')));
    }
  }

  void _showInviteOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.link, color: AppColors.primary),
              title: const Text(
                '링크 초대',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => InviteBottomSheet(roomId: widget.roomId),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: AppColors.primary),
              title: const Text(
                '직접 추가',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => AddMemberDialog(roomId: widget.roomId),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMemberActions(Member m) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                m.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (m.isDirectAdded)
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.primary),
                title: const Text(
                  '정보 변경',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) =>
                        EditMemberDialog(roomId: widget.roomId, member: m),
                  );
                },
              )
            else
              ListTile(
                leading: const Text('👑', style: TextStyle(fontSize: 20)),
                title: const Text(
                  '방장 넘기기',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => TransferHostDialog(
                      memberName: m.name,
                      onConfirm: () => _transferHost(m.name),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: AppColors.error),
              title: const Text(
                '강퇴하기',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.error,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => KickConfirmDialog(
                    memberName: m.name,
                    onConfirm: () => _kickMember(m.name),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text(
                '취소',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 빌드 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final currentUser = ref.watch(authProvider).user;
    final currentUserName = currentUser?.name ?? '';
    final isHost = room.hostId.isNotEmpty && room.hostId == currentUserName;
    final myMember = _findMyMember(room.members, currentUserName);
    final canSearch = myMember?.departure.isNotEmpty == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppHeader(
        title: room.name,
        action: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: _leaveRoom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                '나가기',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _myDepartureSection(myMember),
                  _myTransportSection(myMember),
                  _participantsSection(room, currentUserName, isHost),
                ],
              ),
            ),
          ),
          _bottomSection(canSearch),
        ],
      ),
    );
  }

  // ── 내 출발지 ─────────────────────────────────────────────

  Widget _myDepartureSection(Member? myMember) {
    final address = myMember?.departure ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 출발지',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.radio_button_checked,
                  size: 16,
                  color: address.isEmpty
                      ? AppColors.textHint
                      : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address.isEmpty ? '출발지를 설정해주세요' : address,
                    style: TextStyle(
                      fontSize: 14,
                      color: address.isEmpty
                          ? AppColors.textHint
                          : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (address.isNotEmpty && myMember != null)
                  GestureDetector(
                    onTap: () => context.push(
                      '/room/${widget.roomId}/departure/${myMember.id}',
                    ),
                    child: const Text(
                      '변경',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: '현재 위치',
                  icon: Icons.gps_fixed,
                  filled: true,
                  loading: _isLocating,
                  onTap: () => _setCurrentLocation(myMember),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  label: '주소 검색',
                  icon: Icons.search,
                  filled: false,
                  onTap: myMember != null
                      ? () => context.push(
                          '/room/${widget.roomId}/departure/${myMember.id}',
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool filled,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    final fg = filled ? Colors.white : AppColors.primary;
    return GestureDetector(
      onTap: (loading || onTap == null) ? null : onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.primary),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: fg),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── 내 이동수단 ───────────────────────────────────────────

  Widget _myTransportSection(Member? myMember) {
    final hasAddress = myMember?.departure.isNotEmpty == true;
    final selectedTransit =
        hasAddress && myMember?.transport == TransportMode.transit;
    final selectedCar = hasAddress && myMember?.transport == TransportMode.car;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 이동수단',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _transportModeButton(
                  icon: Icons.directions_transit,
                  label: '대중교통',
                  isSelected: selectedTransit,
                  onTap: myMember != null
                      ? () => _selectTransport(myMember, TransportMode.transit)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _transportModeButton(
                  icon: Icons.directions_car,
                  label: '자동차',
                  isSelected: selectedCar,
                  onTap: myMember != null
                      ? () => _selectTransport(myMember, TransportMode.car)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transportModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 참여자 목록 ───────────────────────────────────────────

  Widget _participantsSection(Room room, String currentUserName, bool isHost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '참여자 (${room.memberCount}명)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showInviteOptions,
                child: const Row(
                  children: [
                    Icon(Icons.person_add, size: 14, color: AppColors.primary),
                    SizedBox(width: 2),
                    Text(
                      '초대 및 직접추가',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...room.members.map(
            (m) => _participantTile(m, currentUserName, isHost, room.hostId),
          ),
        ],
      ),
    );
  }

  Widget _participantTile(
    Member m,
    String currentUserName,
    bool isHost,
    String hostId,
  ) {
    final isCurrentUser = m.name == currentUserName;
    final isMemberHost = m.name == hostId;
    final hasAddress = m.departure.isNotEmpty;
    final showInlineKick = isHost && !isCurrentUser && !hasAddress;
    final canLongPress = isHost && !isCurrentUser;

    return GestureDetector(
      onLongPress: canLongPress ? () => _showMemberActions(m) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    m.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (isMemberHost) ...[
                    const SizedBox(width: 6),
                    _pill('방장', AppColors.primary, Colors.white),
                  ],
                  if (m.isDirectAdded) ...[
                    const SizedBox(width: 6),
                    _pill(
                      '직접추가',
                      const Color(0xFFE8F0FE),
                      const Color(0xFF3D5AFE),
                    ),
                  ],
                  if (hasAddress) ...[
                    const SizedBox(width: 6),
                    Icon(
                      _transportIcon(m.transport),
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
            if (hasAddress)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                  Text(
                    m.departure,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Text(
                    '대기중...',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
                  if (showInlineKick) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => KickConfirmDialog(
                          memberName: m.name,
                          onConfirm: () => _kickMember(m.name),
                        ),
                      ),
                      child: const Text(
                        '강퇴',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // ── 하단 버튼 ─────────────────────────────────────────────

  Widget _bottomSection(bool canSearch) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!canSearch)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '탐색 기준 설정을 먼저 완료해주세요',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      context.push('/room/${widget.roomId}/search-settings'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    '탐색 기준 설정',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: canSearch
                      ? () async {
                          final criteria = ref.read(searchCriteriaProvider);
                          await _apiClient.startSearch(
                            widget.roomId,
                            criteria.name,
                          );
                          if (mounted) {
                            context.push(
                              '/room/${widget.roomId}/search-result',
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.border,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  child: const Text(
                    '중간지점 탐색',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
