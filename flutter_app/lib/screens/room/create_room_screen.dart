import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/room_repository.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_nameCtrl.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // ✅ 서버에 방 만들기 요청
      final repo = RoomRepository();
      final room = await repo.createRoomOnServer(_nameCtrl.text.trim());

      if (room != null) {
        // 서버 성공 → 로컬에도 추가
        ref.read(roomListProvider.notifier).addRoom(room);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방이 만들어졌습니다!')),
          );
          context.pop();
        }
      } else {
        // 서버 실패 → 로컬에만 저장
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('서버 연결 실패 - 로컬에만 저장됩니다'),
              backgroundColor: Colors.orange,
            ),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '방 만들기'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AppTextField(
              label: '방 이름',
              hint: '방 이름을 입력하세요',
              controller: _nameCtrl,
            ),
            const SizedBox(height: 24),
            AppTextField(
              label: '설명',
              hint: '방 설명을 입력하세요',
              controller: _descCtrl,
            ),
            const Spacer(),
            _isLoading
                ? const CircularProgressIndicator(color: AppColors.primary)
                : AppButton(text: '방 만들기', onPressed: _createRoom),
          ],
        ),
      ),
    );
  }
}