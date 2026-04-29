import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/room_provider.dart';

class RoomListScreen extends ConsumerWidget {
  const RoomListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
