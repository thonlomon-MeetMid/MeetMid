import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _joinRoom(Map<String, dynamic> room, {String password = ''}) async {
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
        password: password,
      );
      if (result['ok'] == true && mounted) {
        await ref.read(roomListProvider.notifier).refresh();
        if (mounted) context.push('/room/$roomId');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('403')
            ? '암호가 틀렸습니다'
            : '참여에 실패했습니다';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningRoomId = null);
    }
  }

  Future<void> _showPasswordDialog(Map<String, dynamic> room) async {
    final ctrl = TextEditingController();
    String? errorText;

    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.lock, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('암호 입력',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: InputDecoration(
              hintText: '숫자 4자리',
              counterText: '',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                if (ctrl.text.length != 4) {
                  setS(() => errorText = '4자리를 입력하세요');
                  return;
                }
                Navigator.pop(ctx, ctrl.text);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('확인',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (password != null && mounted) _joinRoom(room, password: password);
  }

  Future<void> _showJoinConfirm(Map<String, dynamic> room) async {
    final hasPassword = room['has_password'] as bool? ?? false;
    if (hasPassword) {
      _showPasswordDialog(room);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('방 참여',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          '\'${room['room_name']}\' 방에 참여하시겠습니까?',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('참여',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _joinRoom(room);
  }

  void _showRoomPreview(Map<String, dynamic> room) {
    final memberNames =
        List<String>.from(room['member_names'] as List? ?? []);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 드래그 핸들
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                room['room_name'] as String,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark),
              ),
              const SizedBox(height: 4),
              Text(
                '${memberNames.length}명 참여 중',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 8),
              if (memberNames.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('참여 중인 멤버가 없습니다.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                )
              else
                ...memberNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.person,
                              color: AppColors.primary, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Text(name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textDark)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showJoinConfirm(room);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('참여하기',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: '방 이름으로 검색',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textHint, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () => _searchCtrl.clear(),
                        child: const Icon(Icons.clear,
                            color: AppColors.textHint, size: 18),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty
                              ? '참여 가능한 방이 없습니다'
                              : '검색 결과가 없습니다',
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRooms,
                        color: AppColors.primary,
                        child: ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _buildRoomCard(_filtered[i]),
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
    final hasPassword = room['has_password'] as bool? ?? false;
    final isJoining = _joiningRoomId == roomId;

    return GestureDetector(
      onTap: isJoining ? null : () => _showRoomPreview(room),
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
                  borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.group,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(roomName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark)),
                      ),
                      if (hasPassword) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock,
                            size: 14, color: AppColors.textSecondary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('$memberCount명 참여 중',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            isJoining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : GestureDetector(
                    onTap: () => _showJoinConfirm(room),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Text('참여',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
