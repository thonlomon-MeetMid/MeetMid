import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../data/services/api_client.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();

  // 아이디 중복 체크 상태: null=미확인, true=가능, false=불가
  bool? _usernameAvailable;
  bool _checkingUsername = false;

  // 이메일 중복 체크 상태
  bool? _emailAvailable;
  bool _checkingEmail = false;

  String? _pwError;
  String? _pwConfirmError;

  static final _pwRegex =
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};:,.<>?]).{8,}$');
  static final _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(_onUsernameFocusChange);
    _emailFocus.addListener(_onEmailFocusChange);
    _pwCtrl.addListener(_validatePassword);
    _pwConfirmCtrl.addListener(_validatePwConfirm);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _onUsernameFocusChange() {
    if (!_usernameFocus.hasFocus && _usernameCtrl.text.trim().isNotEmpty) {
      _checkUsername();
    }
  }

  void _onEmailFocusChange() {
    if (!_emailFocus.hasFocus && _emailCtrl.text.trim().isNotEmpty) {
      _checkEmail();
    }
  }

  Future<void> _checkUsername() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) return;
    setState(() { _checkingUsername = true; _usernameAvailable = null; });
    try {
      final available = await _api.checkUsername(username);
      if (mounted) setState(() { _usernameAvailable = available; _checkingUsername = false; });
    } catch (_) {
      if (mounted) setState(() { _usernameAvailable = null; _checkingUsername = false; });
    }
  }

  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      setState(() { _emailAvailable = false; _checkingEmail = false; });
      return;
    }
    setState(() { _checkingEmail = true; _emailAvailable = null; });
    try {
      final available = await _api.checkEmail(email);
      if (mounted) setState(() { _emailAvailable = available; _checkingEmail = false; });
    } catch (_) {
      if (mounted) setState(() { _emailAvailable = null; _checkingEmail = false; });
    }
  }

  void _validatePassword() {
    final pw = _pwCtrl.text;
    setState(() {
      _pwError = pw.isEmpty ? null
          : !_pwRegex.hasMatch(pw) ? '영문, 숫자, 특수문자 포함 8자 이상이어야 합니다'
          : null;
    });
    if (_pwConfirmCtrl.text.isNotEmpty) _validatePwConfirm();
  }

  void _validatePwConfirm() {
    setState(() {
      _pwConfirmError = _pwConfirmCtrl.text.isEmpty ? null
          : _pwConfirmCtrl.text != _pwCtrl.text ? '비밀번호가 일치하지 않습니다'
          : null;
    });
  }

  bool get _isFormValid {
    return _nameCtrl.text.trim().isNotEmpty &&
        _usernameCtrl.text.trim().isNotEmpty &&
        _usernameAvailable == true &&
        _emailCtrl.text.trim().isNotEmpty &&
        _emailAvailable == true &&
        _pwCtrl.text.isNotEmpty &&
        _pwError == null &&
        _pwConfirmCtrl.text == _pwCtrl.text &&
        _pwConfirmCtrl.text.isNotEmpty;
  }

  Future<void> _handleSignup() async {
    if (!_isFormValid) return;
    final success = await ref.read(authProvider.notifier).register(
          name: _nameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _pwCtrl.text,
        );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해주세요.')),
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
            // 이름
            AppTextField(
              label: '이름',
              hint: '이름을 입력하세요',
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // 아이디
            AppTextField(
              label: '아이디',
              hint: '영문, 숫자 조합',
              controller: _usernameCtrl,
              focusNode: _usernameFocus,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() { _usernameAvailable = null; }),
              suffixIcon: _buildCheckIcon(
                checking: _checkingUsername,
                available: _usernameAvailable,
              ),
            ),
            if (_usernameAvailable != null) ...[
              const SizedBox(height: 4),
              Text(
                _usernameAvailable! ? '사용 가능한 아이디입니다' : '이미 사용 중인 아이디입니다',
                style: TextStyle(
                  fontSize: 12,
                  color: _usernameAvailable! ? AppColors.primary : AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 이메일
            AppTextField(
              label: '이메일',
              hint: '이메일을 입력하세요 (아이디/비밀번호 찾기용)',
              controller: _emailCtrl,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() { _emailAvailable = null; }),
              suffixIcon: _buildCheckIcon(
                checking: _checkingEmail,
                available: _emailAvailable,
              ),
            ),
            if (_emailAvailable != null) ...[
              const SizedBox(height: 4),
              Text(
                _emailAvailable! ? '사용 가능한 이메일입니다' : '이미 사용 중이거나 형식이 올바르지 않습니다',
                style: TextStyle(
                  fontSize: 12,
                  color: _emailAvailable! ? AppColors.primary : AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 비밀번호
            AppTextField(
              label: '비밀번호',
              hint: '영문, 숫자, 특수문자 포함 8자 이상',
              controller: _pwCtrl,
              obscureText: true,
              textInputAction: TextInputAction.next,
            ),
            if (_pwError != null) ...[
              const SizedBox(height: 4),
              Text(_pwError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            const SizedBox(height: 16),

            // 비밀번호 확인
            AppTextField(
              label: '비밀번호 확인',
              hint: '비밀번호를 다시 입력하세요',
              controller: _pwConfirmCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) { if (_isFormValid) _handleSignup(); },
            ),
            if (_pwConfirmError != null) ...[
              const SizedBox(height: 4),
              Text(_pwConfirmError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],

            if (authState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                authState.errorMessage!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
            ],

            const SizedBox(height: 32),

            AppButton(
              text: '계정 생성',
              onPressed: _isFormValid ? _handleSignup : null,
              isLoading: authState.isLoading,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget? _buildCheckIcon({required bool checking, required bool? available}) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textHint),
        ),
      );
    }
    if (available == null) return null;
    return Icon(
      available ? Icons.check_circle : Icons.cancel,
      color: available ? AppColors.primary : AppColors.error,
      size: 20,
    );
  }
}
