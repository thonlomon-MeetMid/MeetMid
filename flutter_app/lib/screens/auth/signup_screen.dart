import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _pwError;
  String? _pwConfirmError;

  // 8자 이상, 영문+숫자+특수문자 각 1개 이상
  static final _pwRegex =
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};:,.<>?]).{8,}$');

  @override
  void initState() {
    super.initState();
    _pwCtrl.addListener(_validatePassword);
    _pwConfirmCtrl.addListener(_validatePasswordConfirm);
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _validatePassword() {
    final pw = _pwCtrl.text;
    setState(() {
      if (pw.isEmpty) {
        _pwError = null;
      } else if (!_pwRegex.hasMatch(pw)) {
        _pwError = '영문, 숫자, 특수문자 포함 8자 이상이어야 합니다';
      } else {
        _pwError = null;
      }
    });
    // 비밀번호가 바뀌면 확인 필드도 재검증
    if (_pwConfirmCtrl.text.isNotEmpty) {
      _validatePasswordConfirm();
    }
  }

  void _validatePasswordConfirm() {
    final confirm = _pwConfirmCtrl.text;
    setState(() {
      if (confirm.isEmpty) {
        _pwConfirmError = null;
      } else if (confirm != _pwCtrl.text) {
        _pwConfirmError = '비밀번호가 일치하지 않습니다';
      } else {
        _pwConfirmError = null;
      }
    });
  }

  bool get _isFormValid {
    return _idCtrl.text.isNotEmpty &&
        _pwCtrl.text.isNotEmpty &&
        _pwRegex.hasMatch(_pwCtrl.text) &&
        _pwConfirmCtrl.text == _pwCtrl.text &&
        _nameCtrl.text.isNotEmpty &&
        _phoneCtrl.text.isNotEmpty;
  }

  void _handleSignup() async {
    if (!_isFormValid) return;

    final success = await ref.read(authProvider.notifier).signup(
          userId: _idCtrl.text,
          password: _pwCtrl.text,
          name: _nameCtrl.text,
          phone: _phoneCtrl.text,
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원가입이 완료되었습니다. 로그인해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: '회원가입'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: '아이디',
              hint: '아이디를 입력하세요',
              controller: _idCtrl,
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: '비밀번호',
              hint: '영문, 숫자, 특수문자 포함 8자 이상',
              controller: _pwCtrl,
              obscureText: true,
            ),
            if (_pwError != null) ...[
              const SizedBox(height: 6),
              Text(
                _pwError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 16),

            AppTextField(
              label: '비밀번호 확인',
              hint: '비밀번호를 다시 입력하세요',
              controller: _pwConfirmCtrl,
              obscureText: true,
            ),
            if (_pwConfirmError != null) ...[
              const SizedBox(height: 6),
              Text(
                _pwConfirmError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 16),

            AppTextField(
              label: '이름',
              hint: '이름을 입력하세요',
              controller: _nameCtrl,
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: '전화번호',
              hint: '전화번호를 입력하세요',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),

            AppButton(
              text: '계정 생성',
              onPressed: _handleSignup,
              isLoading: authState.isLoading,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
