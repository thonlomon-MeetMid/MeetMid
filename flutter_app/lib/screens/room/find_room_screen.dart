import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_header.dart';

class FindRoomScreen extends ConsumerStatefulWidget {
  const FindRoomScreen({super.key});

  @override
  ConsumerState<FindRoomScreen> createState() => _FindRoomScreenState();
}

class _FindRoomScreenState extends ConsumerState<FindRoomScreen> {
  final _searchCtrl = TextEditingController();
  final _api = ApiClient();

  List<Map<String, dynamic>> _allRooms = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String? _joiningRoomId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _loadRooms();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    final userId = ref.read(authProvider).user?.id ?? '';
    try {
      final rooms = await _api.getRoomsAll(userId: userId);
      if (mounted) {
        setState(() {
          _allRooms = rooms;
          _filtered = _applySearch(rooms);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> rooms) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return rooms;
    return rooms
        .where((r) => (r['room_name'] as String).toLowerCase().contains(q))
        .toList();
  }

  void _onSearch() {
    setState(() => _filtered = _applySearch(_allRooms));
  }

  Future<void> _joinRoom(Map<String, dynamic> room) async {
    if (_joiningRoomId != null) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;

    final roomId = room['room_id'] as String;
    setState(() => _joiningRoomId = roomId);
    try {
      final result = await _api.joinRoom(
        roomId: roomId,
        name: user.name,
        address: '',
        transport: 'transit',
        userUuid: user.id,
      );
      if (result['ok'] == true && mounted) {
        await ref.read(roomListProvider.notifier).refresh();
        if (mounted) context.push('/room/$roomId');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('참여에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningRoomId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: '방 찾기'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: '방 이름으로 검색',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () => _searchCtrl.clear(),
                        child: const Icon(Icons.clear, color: AppColors.textHint, size: 18),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty ? '참여 가능한 방이 없습니다' : '검색 결과가 없습니다',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRooms,
                        color: AppColors.primary,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (context, i) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _buildRoomCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final roomId = room['room_id'] as String;
    final roomName = room['room_name'] as String;
    final memberCount = room['member_count'] as int? ?? 0;
    final isJoining = _joiningRoomId == roomId;

    return GestureDetector(
      onTap: isJoining ? null : () => _joinRoom(room),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.group, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$memberCount명 참여 중',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            isJoining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '참여',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
