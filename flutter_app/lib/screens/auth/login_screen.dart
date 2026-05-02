import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _usernameFocus = FocusNode();
  final _pwFocus = FocusNode();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _pwCtrl.dispose();
    _usernameFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_usernameCtrl.text.trim().isEmpty || _pwCtrl.text.isEmpty) return;
    final success = await ref.read(authProvider.notifier).login(
          _usernameCtrl.text.trim(),
          _pwCtrl.text,
        );
    if (success && mounted) context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 80),

              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.place, color: AppColors.primary, size: 36),
              ),
              const SizedBox(height: 16),

              const Text(
                'MeetMid',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '만남의 중간 지점 찾기',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),

              const SizedBox(height: 48),

              AppTextField(
                label: '아이디',
                hint: '아이디를 입력하세요',
                controller: _usernameCtrl,
                focusNode: _usernameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _pwFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: '비밀번호',
                hint: '비밀번호를 입력하세요',
                controller: _pwCtrl,
                focusNode: _pwFocus,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
              ),

              if (authState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  authState.errorMessage!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ],

              const SizedBox(height: 24),

              AppButton(
                text: '로그인',
                onPressed: _handleLogin,
                isLoading: authState.isLoading,
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _linkButton('회원가입', () => context.push('/auth/signup')),
                  _divider(),
                  _linkButton('아이디 찾기', () => context.push('/auth/find-id')),
                  _divider(),
                  _linkButton('비밀번호 찾기', () => context.push('/auth/find-pw')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkButton(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 12, color: AppColors.border);
}
