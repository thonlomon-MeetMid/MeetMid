import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  final FocusNode _idFocus = FocusNode();
  final FocusNode _pwFocus = FocusNode();

  bool _obscure = true;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _idFocus.addListener(() => setState(() {}));
    _pwFocus.addListener(() => setState(() {}));
    _loadSavedUsername();
  }

  Future<void> _loadSavedUsername() async {
    final repo = ref.read(authRepositoryProvider);
    final saved = await repo.loadSavedUsername();
    if (saved != null && mounted) {
      setState(() => _idCtrl.text = saved);
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _idFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();
    final username = _idCtrl.text.trim();
    final password = _pwCtrl.text;
    if (username.isEmpty || password.isEmpty) return;

    final repo = ref.read(authRepositoryProvider);
    if (_remember) {
      await repo.saveUsername(username);
    } else {
      await repo.clearSavedUsername();
    }

    final success =
        await ref.read(authProvider.notifier).login(username, password);
    if (success && mounted) context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEEF3FF), Color(0xFFFFFFFF), Color(0xFFF6F9FF)],
            stops: [0.0, 0.42, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical -
                    30,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    _buildHero(),
                    const SizedBox(height: 38),
                    _buildLabel('아이디'),
                    const SizedBox(height: 9),
                    _buildField(
                      controller: _idCtrl,
                      focusNode: _idFocus,
                      hint: '아이디를 입력하세요',
                      leadingIcon: Icons.person_outline_rounded,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _pwFocus.requestFocus(),
                    ),
                    const SizedBox(height: 18),
                    _buildLabel('비밀번호'),
                    const SizedBox(height: 9),
                    _buildField(
                      controller: _pwCtrl,
                      focusNode: _pwFocus,
                      hint: '비밀번호를 입력하세요',
                      leadingIcon: Icons.lock_outline_rounded,
                      obscure: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onLogin(),
                      trailing: IconButton(
                        splashRadius: 20,
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.brandMuted,
                          size: 21,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildOptionsRow(),
                    if (authState.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        authState.errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                          letterSpacing: -0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 26),
                    _buildLoginButton(isLoading: authState.isLoading),
                    const Spacer(),
                    const SizedBox(height: 22),
                    _buildFooterLinks(),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 히어로: "4명이 서로 다른 거리에서 중간 핀으로 모인다" 장면 ──
  Widget _buildHero() {
    return Column(
      children: [
        SizedBox(
          width: 308,
          height: 172,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _RoutesPainter())),
              Positioned(
                left: 5,
                top: 119,
                child: _person(const [Color(0xFFFF9472), Color(0xFFFF7A57)]),
              ),
              Positioned(
                left: 25,
                top: 7,
                child: _person(const [Color(0xFFFFCB7A), Color(0xFFFFB347)]),
              ),
              Positioned(
                left: 251,
                top: 113,
                child: _person(const [Color(0xFFFFA0C0), Color(0xFFFF6F9C)]),
              ),
              Positioned(
                left: 269,
                top: 21,
                child: _person(const [Color(0xFFB3A8FF), Color(0xFF8C7CF1)]),
              ),
              const Positioned(left: 110, top: 8, child: _MidpointMark()),
            ],
          ),
        ),
        const SizedBox(height: 18),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.brandInk,
            ),
            children: [
              TextSpan(text: 'Meet'),
              TextSpan(
                text: 'Mid',
                style: TextStyle(color: AppColors.brandPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.brandMutedDeep,
              letterSpacing: -0.3,
            ),
            children: [
              TextSpan(text: '우리, '),
              TextSpan(
                text: '딱 중간',
                style: TextStyle(
                  color: AppColors.brandCoral,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: '에서 만나요'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _person(List<Color> gradient) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(color: AppColors.brandBg, width: 2.5),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: gradient.last.withOpacity(0.5),
            blurRadius: 18,
            offset: const Offset(0, 9),
            spreadRadius: -7,
          ),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 19),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.brandInkSoft,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData leadingIcon,
    bool obscure = false,
    Widget? trailing,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    final bool focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 58,
      padding: const EdgeInsets.only(left: 18, right: 6),
      decoration: BoxDecoration(
        color: focused ? Colors.white : AppColors.brandField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused ? AppColors.brandPrimary : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: AppColors.brandPrimary.withOpacity(0.12),
                  blurRadius: 0,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            leadingIcon,
            size: 20,
            color: focused ? AppColors.brandPrimary : AppColors.brandMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
              cursorColor: AppColors.brandPrimary,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.brandInk,
                letterSpacing: -0.2,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFF9AA6B6),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing else const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildOptionsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _remember = !_remember),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _remember ? AppColors.brandPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _remember
                          ? AppColors.brandPrimary
                          : AppColors.brandFieldBorder,
                      width: 1.8,
                    ),
                  ),
                  child: _remember
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 9),
                const Text(
                  '아이디 저장',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandMutedDeep,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton({required bool isLoading}) {
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.brandPrimaryBright,
              AppColors.brandPrimary,
              AppColors.brandPrimaryDeep,
            ],
            stops: [0.0, 0.6, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: AppColors.brandPrimary.withOpacity(0.7),
              blurRadius: 30,
              offset: const Offset(0, 16),
              spreadRadius: -10,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isLoading ? null : _onLogin,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '로그인',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _footerLink('회원가입', strong: true,
            onTap: () => context.push('/auth/signup')),
        _divider(),
        _footerLink('아이디 찾기',
            onTap: () => context.push('/auth/find-id')),
        _divider(),
        _footerLink('비밀번호 찾기',
            onTap: () => context.push('/auth/find-pw')),
      ],
    );
  }

  Widget _footerLink(String text,
      {bool strong = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          color: strong ? AppColors.brandInkSoft : AppColors.brandMutedDeep,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 13,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.brandLine,
    );
  }
}

// ── 4명 → 중앙 수렴 점선 경로 (308×172 기준 좌표) ──────────────────────
class _RoutesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double sx = size.width / 308.0;
    final double sy = size.height / 172.0;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    _dashedPath(
      canvas,
      Path()
        ..moveTo(p(24, 138).dx, p(24, 138).dy)
        ..cubicTo(p(70, 130).dx, p(70, 130).dy, p(96, 108).dx, p(96, 108).dy,
            p(124, 90).dx, p(124, 90).dy),
      // ignore: deprecated_member_use
      const Color(0xFFFF7A57).withOpacity(0.8),
    );
    _dashedPath(
      canvas,
      Path()
        ..moveTo(p(44, 26).dx, p(44, 26).dy)
        ..cubicTo(p(80, 20).dx, p(80, 20).dy, p(100, 24).dx, p(100, 24).dy,
            p(122, 32).dx, p(122, 32).dy),
      // ignore: deprecated_member_use
      const Color(0xFFFFB347).withOpacity(0.85),
    );
    _dashedPath(
      canvas,
      Path()
        ..moveTo(p(270, 132).dx, p(270, 132).dy)
        ..cubicTo(
            p(232, 126).dx, p(232, 126).dy,
            p(208, 104).dx, p(208, 104).dy,
            p(186, 90).dx, p(186, 90).dy),
      // ignore: deprecated_member_use
      const Color(0xFFFF6F9C).withOpacity(0.8),
    );
    _dashedPath(
      canvas,
      Path()
        ..moveTo(p(288, 40).dx, p(288, 40).dy)
        ..cubicTo(p(252, 38).dx, p(252, 38).dy, p(220, 42).dx, p(220, 42).dy,
            p(192, 48).dx, p(192, 48).dy),
      // ignore: deprecated_member_use
      const Color(0xFF8C7CF1).withOpacity(0.85),
    );
  }

  void _dashedPath(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const double dash = 2.0;
    const double gap = 8.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 중앙 미트포인트 마크: 핑 링 2개 + 글래스 스퀴클 + 위치 핀 ────────────
class _MidpointMark extends StatelessWidget {
  const _MidpointMark();

  static Widget _ping(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          // ignore: deprecated_member_use
          color: AppColors.brandPrimary.withOpacity(opacity),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _ping(148, 0.10),
          _ping(118, 0.18),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6B83FF),
                  AppColors.brandPrimary,
                  AppColors.brandPrimaryDeep,
                ],
                stops: [0.0, 0.52, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: AppColors.brandPrimary.withOpacity(0.6),
                  blurRadius: 40,
                  offset: const Offset(0, 22),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 50,
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.location_on, color: Colors.white, size: 44),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
