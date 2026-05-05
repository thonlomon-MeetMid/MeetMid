import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/app_header.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String _selectedLanguage = '한국어';

  final List<String> _languages = ['한국어', 'English'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '언어 설정'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _languages
            .map((lang) => GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = lang),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _selectedLanguage == lang
                          ? AppColors.infoBannerBg
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedLanguage == lang
                            ? AppColors.primary
                            : AppColors.border,
                        width: _selectedLanguage == lang ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedLanguage == lang
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: _selectedLanguage == lang
                              ? AppColors.primary
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          lang,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textDark,
                            fontWeight: _selectedLanguage == lang
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}