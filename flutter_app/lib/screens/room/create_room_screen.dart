import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/room.dart';
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _createRoom() {
    if (_nameCtrl.text.isEmpty) return;
    final room = Room(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text,
      description: _descCtrl.text,
      memberCount: 0,
      members: [],
    );
    ref.read(roomListProvider.notifier).addRoom(room);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '방 만들기'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AppTextField(label: '방 이름', hint: '방 이름을 입력하세요', controller: _nameCtrl),
            const SizedBox(height: 24),
            AppTextField(label: '설명', hint: '방 설명을 입력하세요', controller: _descCtrl),
            const Spacer(),
            AppButton(text: '방 만들기', onPressed: _createRoom),
          ],
        ),
      ),
    );
  }
}
