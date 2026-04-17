import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
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
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: '아이디 찾기'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AppTextField(label: '이름', hint: '이름을 입력하세요', controller: _nameCtrl),
            const SizedBox(height: 16),
            AppTextField(label: '전화번호', hint: '전화번호를 입력하세요', controller: _phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 32),
            AppButton(text: '아이디 찾기', onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
