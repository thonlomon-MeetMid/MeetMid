import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
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
  final _passwordCtrl = TextEditingController();
  String? _passwordError;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    final pw = _passwordCtrl.text;
    if (pw.isNotEmpty && pw.length != 4) {
      setState(() => _passwordError = '암호는 숫자 4자리여야 합니다');
      return false;
    }
    setState(() => _passwordError = null);
    return true;
  }

  Future<void> _createRoom() async {
    if (_nameCtrl.text.isEmpty) return;
    if (!_validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authProvider).user;
      final room = await ref.read(roomListProvider.notifier).createRoom(
            _nameCtrl.text.trim(),
            hostName: user?.name ?? '',
            hostUuid: user?.id ?? '',
            password: _passwordCtrl.text.trim(),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(room != null ? '방이 만들어졌습니다!' : '서버 연결 실패 - 로컬에만 저장됩니다'),
          backgroundColor: room != null ? null : Colors.orange,
        ),
      );
      context.pop();
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '방 암호',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '선택',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    if (_passwordError != null) _validate();
                  },
                  decoration: InputDecoration(
                    hintText: '숫자 4자리 (입력 안 하면 공개방)',
                    hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.inputBackground,
                    counterText: '',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18, color: AppColors.textHint),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _passwordError,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  ),
                ),
              ],
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