import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.read(roomListProvider.notifier).silentRefresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('방 목록'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () => ref.read(roomListProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary),
            onPressed: () => context.push('/room/create'),
          ),
        ],
      ),
      body: roomsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                '방 목록을 불러오지 못했습니다\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(roomListProvider.notifier).refresh(),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (rooms) => rooms.isEmpty
            ? const Center(
                child: Text(
                  '참여 중인 방이 없습니다',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rooms.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  return GestureDetector(
                    onTap: () => context.push('/room/${room.id}'),
                    onLongPress: () async {
                      final action = await showModalBottomSheet<String>(
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
                              const SizedBox(height: 4),
                              ListTile(
                                leading: const Icon(Icons.exit_to_app, color: AppColors.error),
                                title: Text(
                                  '${room.name} 나가기',
                                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w500),
                                ),
                                onTap: () => Navigator.pop(context, 'leave'),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                      if (action != 'leave' || !context.mounted) return;

                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('방 나가기'),
                          content: Text('정말 "${room.name}"에서 나가시겠습니까?'),
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
                      if (confirmed != true || !context.mounted) return;

                      final userName = ref.read(authProvider).user?.name ?? '';
                      final success = await ref.read(roomListProvider.notifier).leaveRoom(
                        roomId: room.id,
                        userName: userName,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? '"${room.name}"에서 나갔습니다' : '방 나가기에 실패했습니다'),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.people,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  room.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${room.memberCount}명 참여 중',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textHint),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
