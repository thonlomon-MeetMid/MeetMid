import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class GreenHillsBackground extends StatelessWidget {
  const GreenHillsBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 240,
      child: CustomPaint(painter: _HillsPainter()),
    );
  }
}

class _HillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 뒤쪽 밝은 언덕
    final lightPaint = Paint()..color = AppColors.hillGreen.withValues(alpha: 0.7);
    final lightPath = Path()
      ..moveTo(-50, size.height * 0.4)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.2,
        size.width + 50,
        size.height * 0.5,
      )
      ..lineTo(size.width + 50, size.height)
      ..lineTo(-50, size.height)
      ..close();
    canvas.drawPath(lightPath, lightPaint);

    // 앞쪽 짙은 언덕
    final darkPaint = Paint()..color = AppColors.hillDarkGreen.withValues(alpha: 0.85);
    final darkPath = Path()
      ..moveTo(-30, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.1,
        size.width + 30,
        size.height * 0.65,
      )
      ..lineTo(size.width + 30, size.height)
      ..lineTo(-30, size.height)
      ..close();
    canvas.drawPath(darkPath, darkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
