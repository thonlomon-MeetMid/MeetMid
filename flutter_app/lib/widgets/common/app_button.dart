import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

enum AppButtonVariant { primary, outlined, kakao, danger }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final double? height;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final h = height ?? 48.0;

    switch (variant) {
      case AppButtonVariant.primary:
        return SizedBox(
          width: double.infinity,
          height: h,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _buildChild(Colors.white),
          ),
        );
      case AppButtonVariant.outlined:
        return SizedBox(
          width: double.infinity,
          height: h,
          child: OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textDark,
              side: const BorderSide(color: AppColors.borderLight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _buildChild(AppColors.textDark),
          ),
        );
      case AppButtonVariant.kakao:
        return SizedBox(
          width: double.infinity,
          height: h,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kakaoYellow,
              foregroundColor: AppColors.kakaoBrown,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _buildChild(AppColors.kakaoBrown),
          ),
        );
      case AppButtonVariant.danger:
        return SizedBox(
          width: double.infinity,
          height: h,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _buildChild(Colors.white),
          ),
        );
    }
  }

  Widget _buildChild(Color color) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        ],
      );
    }
    return Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color));
  }
}
