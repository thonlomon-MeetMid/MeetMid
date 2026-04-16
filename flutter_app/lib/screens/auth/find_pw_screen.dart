import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';
import '../../widgets/common/app_text_field.dart';

class FindPwScreen extends StatefulWidget {
  const FindPwScreen({super.key});

  @override
  State<FindPwScreen> createState() => _FindPwScreenState();
}

class _FindPwScreenState extends State<FindPwScreen> {
  final _idCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: '비밀번호 찾기'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AppTextField(label: '아이디', hint: '아이디를 입력하세요', controller: _idCtrl),
            const SizedBox(height: 16),
            AppTextField(label: '전화번호', hint: '전화번호를 입력하세요', controller: _phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 32),
            AppButton(text: '비밀번호 찾기', onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
