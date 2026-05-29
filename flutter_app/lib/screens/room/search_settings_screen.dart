import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/search_criteria.dart';
import '../../providers/place_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/search_provider.dart';

// ── 디자인 토큰 (이 파일 전용) ─────────────────────────────────────
const _kFont = 'Pretendard';
const _kRadius = 16.0;

class _C {
  static const accent = Color(0xFF3B5DFF);
  static const ink = Color(0xFF1A1D23);
  static const sub = Color(0xFF8A9099);
  static const sub2 = Color(0xFF6B7280);
  static const chipBg = Color(0xFFF1F2F4);
  static const chipInk = Color(0xFF2B2F36);
  static const cardBorder = Color(0xFFECECEF);
  static const divider = Color(0xFFF0F1F3);
  static const mapBg = Color(0xFFEAEEF5);
  static const radioOff = Color(0xFFC7CCD4);
}

Color _aa(double o) => _C.accent.withValues(alpha: o);

// ── 카테고리 데이터 ────────────────────────────────────────────────
const List<(String, String)> _kCats = [
  ('', '전체'),
  ('FD6', '식당'),
  ('CE7', '카페'),
  ('CS2', '편의점'),
  ('CT1', '문화시설'),
];

// 지도 미리보기 후보 마커 (left%, top%, big)
const List<(double, double, bool)> _kPlaces = [
  (0.43, 0.38, true),
  (0.60, 0.46, false),
  (0.47, 0.63, false),
  (0.37, 0.56, false),
  (0.59, 0.60, true),
];

// ── 화면 ──────────────────────────────────────────────────────────
class SearchSettingsScreen extends ConsumerStatefulWidget {
  final String roomId;
  const SearchSettingsScreen({super.key, required this.roomId});

  @override
  ConsumerState<SearchSettingsScreen> createState() =>
      _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends ConsumerState<SearchSettingsScreen>
    with TickerProviderStateMixin {
  late String _cat;
  late SearchCriteria _crit;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _cat = ref.read(selectedCategoryCodeProvider);
    _crit = ref.read(searchCriteriaProvider);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _done() {
    ref.read(selectedCategoryCodeProvider.notifier).state = _cat;
    ref.read(searchCriteriaProvider.notifier).state = _crit;
    context.go('/room/${widget.roomId}');
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? [];
    final room = rooms.where((r) => r.id == widget.roomId).firstOrNull;
    final memberCount = room?.members.length ?? 3;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('어디 가세요?'),
                    const SizedBox(height: 10),
                    _CategoryChips(
                      value: _cat,
                      onChanged: (v) => setState(() => _cat = v),
                    ),
                    const SizedBox(height: 12),
                    _MapPreview(
                        entrance: _entrance,
                        pulse: _pulse,
                        memberCount: memberCount),
                    const SizedBox(height: 8),
                    _guideLine(),
                    const SizedBox(height: 14),
                    _sectionTitle('탐색 기준'),
                    const SizedBox(height: 10),
                    ...SearchCriteria.values.map((c) => Padding(
                          padding: EdgeInsets.only(
                              bottom: c == SearchCriteria.values.last ? 0 : 8),
                          child: _CriteriaCard(
                            title: c.label,
                            desc: c.description,
                            selected: _crit == c,
                            onTap: () => setState(() => _crit = c),
                          ),
                        )),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _C.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 20, color: _C.ink),
              ),
            ),
            const Expanded(
              child: Text(
                '탐색 기준 설정',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _C.ink),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: _C.ink),
      );

  Widget _guideLine() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.schedule, size: 17, color: _C.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13.5,
                    height: 1.5,
                    color: _C.sub2),
                children: [
                  TextSpan(
                    text: '중간 지점 500m 근방',
                    style: TextStyle(
                        color: _C.ink, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '의 가장 별점 높은 장소를 안내해드려요.'),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _footer() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _C.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _done,
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.accent,
              foregroundColor: Colors.white,
              elevation: 6,
              shadowColor: _aa(0.4),
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kRadius)),
            ),
            child: const Text('설정 완료',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

// ── 카테고리 칩 ───────────────────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CategoryChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _kCats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _chip(_kCats[i].$1, _kCats[i].$2)),
        ],
      ],
    );
  }

  Widget _chip(String id, String label) {
    final on = id == value;
    return GestureDetector(
      onTap: () => onChanged(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _C.accent : _C.chipBg,
          borderRadius: BorderRadius.circular(_kRadius),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: _aa(0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 15,
            fontWeight: on ? FontWeight.w700 : FontWeight.w600,
            color: on ? Colors.white : _C.chipInk,
          ),
        ),
      ),
    );
  }
}

// ── 탐색 기준 카드 ────────────────────────────────────────────────
class _CriteriaCard extends StatelessWidget {
  final String title, desc;
  final bool selected;
  final VoidCallback onTap;
  const _CriteriaCard(
      {required this.title,
      required this.desc,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? _aa(0.07) : Colors.white,
          borderRadius: BorderRadius.circular(_kRadius),
          border: Border.all(
            color: selected ? _C.accent : _C.cardBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            _radio(selected),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _C.ink)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13.5,
                          color: _C.sub)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radio(bool on) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: on ? _C.accent : _C.radioOff, width: 2),
        ),
        child: on
            ? Container(
                width: 11,
                height: 11,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: _C.accent),
              )
            : null,
      );
}

// ── 지도 미리보기 ─────────────────────────────────────────────────
class _MapPreview extends StatelessWidget {
  final AnimationController entrance;
  final AnimationController pulse;
  final int memberCount;
  const _MapPreview(
      {required this.entrance,
      required this.pulse,
      required this.memberCount});

  static const double _circle = 116;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kRadius),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: _C.mapBg,
          border: Border.all(color: const Color(0xFFE8EAEF)),
        ),
        child: Stack(
          children: [
            _road(top: 0.36, height: 10, angle: -8),
            _road(top: 0.66, height: 14, angle: 4),
            _roadV(left: 0.47, width: 12, angle: 6),
            _roadV(left: 0.20, width: 7, angle: -3),
            Positioned(
              top: 9,
              left: 220,
              child: _block(84, 52, const Color(0xFFDBEADD)),
            ),
            Positioned(
              bottom: 8,
              right: 18,
              child: _block(70, 44, const Color(0xFFE2E6EE)),
            ),
            Center(
              child: CustomPaint(
                size: const Size(_circle, _circle),
                painter: _DashedCirclePainter(_C.accent),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (_, __) {
                  final v = pulse.value;
                  final scale = 0.35 + 0.65 * v;
                  final op = (0.55 * (1 - v / 0.8)).clamp(0.0, 0.55);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: _circle,
                      height: _circle,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _C.accent.withValues(alpha: op),
                            width: 2),
                      ),
                    ),
                  );
                },
              ),
            ),
            for (int i = 0; i < _kPlaces.length; i++)
              _placeMarker(_kPlaces[i], i),
            Center(
              child: Container(
                width: 20,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0x331E1E3C),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: entrance,
                builder: (_, child) {
                  final t = const Interval(0.07, 0.6, curve: Curves.easeOutBack)
                      .transform(entrance.value);
                  final dy = (1 - t) * -16;
                  final op = entrance.value < 0.07 ? 0.0 : 1.0;
                  return Transform.translate(
                    offset: Offset(0, -23 + dy),
                    child: Opacity(opacity: op, child: child),
                  );
                },
                child: const SizedBox(
                  width: 44,
                  height: 46,
                  child: CustomPaint(painter: _FlagPainter()),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _pill(
                bg: Colors.white,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group, size: 15, color: _C.accent),
                    const SizedBox(width: 6),
                    Text('$memberCount명',
                        style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _C.ink)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _pill(
                bg: _C.accent,
                child: const Text('반경 500m',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeMarker((double, double, bool) p, int i) {
    final start = (250 + i * 120) / 1400;
    final end = math.min(1.0, (750 + i * 120) / 1400);
    final anim = CurvedAnimation(
      parent: entrance,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );
    final big = p.$3;
    return Align(
      alignment: Alignment(p.$1 * 2 - 1, p.$2 * 2 - 1),
      child: ScaleTransition(
        scale: anim,
        child: Container(
          width: big ? 14 : 10,
          height: big ? 14 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: big ? _C.accent : Colors.white,
            border: Border.all(
                color: big ? Colors.white : _C.accent, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x381E1E3C),
                  blurRadius: 5,
                  offset: Offset(0, 2))
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill({required Color bg, required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          boxShadow: bg == Colors.white
              ? const [
                  BoxShadow(
                      color: Color(0x1F1E1E3C),
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ]
              : null,
        ),
        child: child,
      );

  Widget _road({required double top, required double height, required double angle}) =>
      Align(
        alignment: Alignment(0, top * 2 - 1),
        child: FractionallySizedBox(
          widthFactor: 1.2,
          child: Transform.rotate(
            angle: angle * math.pi / 180,
            child: Container(height: height, color: Colors.white),
          ),
        ),
      );

  Widget _roadV({required double left, required double width, required double angle}) =>
      Align(
        alignment: Alignment(left * 2 - 1, 0),
        child: FractionallySizedBox(
          heightFactor: 1.2,
          child: Transform.rotate(
            angle: angle * math.pi / 180,
            child: Container(width: width, color: Colors.white),
          ),
        ),
      );

  Widget _block(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
      );
}

// ── 점선 원 ───────────────────────────────────────────────────────
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  const _DashedCirclePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawOval(rect, Paint()..color = color.withValues(alpha: 0.10));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const dash = 6.0, gap = 5.0;
    final path = Path()..addOval(rect);
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final len = math.min(dash, m.length - d);
        canvas.drawPath(m.extractPath(d, d + len), stroke);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) =>
      old.color != color;
}

// ── 빨간 깃발 ─────────────────────────────────────────────────────
class _FlagPainter extends CustomPainter {
  const _FlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 44, sy = size.height / 46;
    final pole = Paint()..color = const Color(0xFF3A3F4A);
    canvas.drawRRect(
      RRect.fromLTRBR(
          20.5 * sx, 5 * sy, 23.5 * sx, 42 * sy, Radius.circular(1.5 * sx)),
      pole,
    );
    canvas.drawCircle(Offset(22 * sx, 5 * sy), 2.6 * sx, pole);
    final path = Path()
      ..moveTo(23.5 * sx, 6.2 * sy)
      ..lineTo(43 * sx, 9.4 * sy)
      ..cubicTo(40 * sx, 12 * sy, 40 * sx, 15 * sy, 43 * sx, 17.6 * sy)
      ..lineTo(23.5 * sx, 20.8 * sy)
      ..close();
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF5A52), Color(0xFFE5392F)],
    ).createShader(Rect.fromLTWH(23.5 * sx, 6.2 * sy, 20 * sx, 15 * sy));
    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => false;
}
