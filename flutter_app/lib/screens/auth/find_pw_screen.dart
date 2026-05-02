import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class FindPwScreen extends StatefulWidget {
  const FindPwScreen({super.key});

  @override
  State<FindPwScreen> createState() => _FindPwScreenState();
}

class _FindPwScreenState extends State<FindPwScreen> {
  // 1단계
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  // 2단계
  final _newPwCtrl = TextEditingController();
  final _newPwConfirmCtrl = TextEditingController();

  int _step = 1; // 1 = 본인 확인, 2 = 새 비밀번호 설정
  bool _isLoading = false;
  String? _errorMsg;
  String? _pwError;
  String? _pwConfirmError;

  static final _pwRegex =
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};:,.<>?]).{8,}$');

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _newPwCtrl.addListener(_validatePw);
    _newPwConfirmCtrl.addListener(_validatePwConfirm);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _newPwCtrl.dispose();
    _newPwConfirmCtrl.dispose();
    super.dispose();
  }

  void _validatePw() {
    final pw = _newPwCtrl.text;
    setState(() {
      _pwError = pw.isEmpty ? null
          : !_pwRegex.hasMatch(pw) ? '영문, 숫자, 특수문자 포함 8자 이상이어야 합니다'
          : null;
    });
    if (_newPwConfirmCtrl.text.isNotEmpty) _validatePwConfirm();
  }

  void _validatePwConfirm() {
    setState(() {
      _pwConfirmError = _newPwConfirmCtrl.text.isEmpty ? null
          : _newPwConfirmCtrl.text != _newPwCtrl.text ? '비밀번호가 일치하지 않습니다'
          : null;
    });
  }

  bool get _step1Valid =>
      _usernameCtrl.text.trim().isNotEmpty && _emailCtrl.text.trim().isNotEmpty;

  bool get _step2Valid =>
      _newPwCtrl.text.isNotEmpty &&
      _pwError == null &&
      _newPwConfirmCtrl.text == _newPwCtrl.text &&
      _newPwConfirmCtrl.text.isNotEmpty;

  Future<void> _verify() async {
    if (!_step1Valid) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      await _api.verifyForReset(
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
      if (mounted) setState(() { _step = 2; _isLoading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMsg = '아이디 또는 이메일이 올바르지 않습니다';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!_step2Valid) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      await _api.resetPassword(
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        newPassword: _newPwCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 변경되었습니다. 다시 로그인해주세요.')),
      );
      context.go('/auth/login');
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMsg = '비밀번호 변경에 실패했습니다';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: '비밀번호 찾기',
        action: _step == 2
            ? Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('2/2', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              )
            : Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('1/2', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _step == 1 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '가입 시 등록한 아이디와 이메일을 입력하세요',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: '아이디',
          hint: '아이디를 입력하세요',
          controller: _usernameCtrl,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: '이메일',
          hint: '가입 시 입력한 이메일',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _verify(),
        ),
        if (_errorMsg != null) ...[
          const SizedBox(height: 12),
          Text(_errorMsg!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
        ],
        const SizedBox(height: 32),
        AppButton(
          text: '본인 확인',
          onPressed: _step1Valid ? _verify : null,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '새로운 비밀번호를 설정하세요',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: '새 비밀번호',
          hint: '영문, 숫자, 특수문자 포함 8자 이상',
          controller: _newPwCtrl,
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        if (_pwError != null) ...[
          const SizedBox(height: 4),
          Text(_pwError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
        ],
        const SizedBox(height: 16),
        AppTextField(
          label: '새 비밀번호 확인',
          hint: '비밀번호를 다시 입력하세요',
          controller: _newPwConfirmCtrl,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) { if (_step2Valid) _resetPassword(); },
        ),
        if (_pwConfirmError != null) ...[
          const SizedBox(height: 4),
          Text(_pwConfirmError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
        ],
        if (_errorMsg != null) ...[
          const SizedBox(height: 12),
          Text(_errorMsg!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
        ],
        const SizedBox(height: 32),
        AppButton(
          text: '비밀번호 변경',
          onPressed: _step2Valid ? _resetPassword : null,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
