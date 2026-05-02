import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class FindIdScreen extends StatefulWidget {
  const FindIdScreen({super.key});

  @override
  State<FindIdScreen> createState() => _FindIdScreenState();
}

class _FindIdScreenState extends State<FindIdScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;
  String? _foundUsername;
  String? _errorMsg;

  final _api = ApiClient();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _canSearch =>
      _nameCtrl.text.trim().isNotEmpty && _emailCtrl.text.trim().isNotEmpty;

  Future<void> _findId() async {
    if (!_canSearch) return;
    setState(() { _isLoading = true; _foundUsername = null; _errorMsg = null; });
    try {
      final username = await _api.findUsername(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
      if (mounted) setState(() { _foundUsername = username; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = '일치하는 계정을 찾을 수 없습니다';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: '아이디 찾기'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: '이름',
              hint: '가입 시 입력한 이름',
              controller: _nameCtrl,
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
              onSubmitted: (_) => _findId(),
            ),
            const SizedBox(height: 32),

            AppButton(
              text: '아이디 찾기',
              onPressed: _canSearch ? _findId : null,
              isLoading: _isLoading,
            ),

            // 결과 영역
            if (_foundUsername != null) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      '회원님의 아이디',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _foundUsername!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: '로그인하기',
                      onPressed: () => context.go('/auth/login'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      text: '비밀번호 찾기',
                      variant: AppButtonVariant.outlined,
                      onPressed: () => context.push('/auth/find-pw'),
                    ),
                  ),
                ],
              ),
            ],

            if (_errorMsg != null) ...[
              const SizedBox(height: 20),
              Text(
                _errorMsg!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
