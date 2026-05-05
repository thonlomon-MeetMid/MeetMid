// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../providers/room_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_header.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  final String roomId;
  const SearchResultScreen({super.key, required this.roomId});

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends ConsumerState<SearchResultScreen> {
  bool _mapLoading = true;
  bool _mapInitStarted = false;
  final _api = ApiClient();
  final _mapKey = GlobalKey();
  List<Map<String, dynamic>> _memberPositions = [];
  String _midAddress = '중간 지점';
  Map<String, int> _memberMinutes = {};
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMapInit());
  }

  @override
  void dispose() {
    try {
      js.context.callMethod('flutterDestroyKakaoMap', []);
    } catch (_) {}
    super.dispose();
  }

  // ── 지도 초기화 ──────────────────────────────────────────────

  void _startMapInit() {
    if (_mapInitStarted) return;
    _mapInitStarted = true;
    try {
      js.context.callMethod('flutterCreateKakaoMapInBody', [37.5665, 126.9780]);
    } catch (e) {
      debugPrint('카카오맵 초기화 오류: $e');
      if (mounted) setState(() => _mapLoading = false);
      return;
    }
    _pollMapReady();
  }

  Future<void> _pollMapReady() async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (js.context['_kakaoMapReady'] == true) {
        await Future.delayed(const Duration(milliseconds: 300));
        await _loadMemberMarkers();
        if (mounted) setState(() => _mapLoading = false);
        // 지도 div를 실제 보이는 280px 영역에 정확히 맞춤 → fitBounds가 그 영역 기준으로 zoom 계산
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _applyMapViewport();
          await Future.delayed(const Duration(milliseconds: 200));
          try {
            js.context.callMethod('flutterFitBounds', []);
          } catch (_) {}
        });
        return;
      }
    }
    if (mounted) setState(() => _mapLoading = false);
  }

  // 보이는 지도 영역의 실제 화면 좌표를 측정해 JS에 전달
  void _applyMapViewport() {
    final ctx = _mapKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    try {
      js.context.callMethod('flutterSetMapBounds',
          [topLeft.dy, topLeft.dx, size.width, size.height]);
    } catch (_) {}
  }

  Future<void> _loadMemberMarkers() async {
    final criteria = ref.read(searchCriteriaProvider);
    try {
      final result = await _api.getMidpoint(
        widget.roomId,
        criteria: criteria.name,
      );

      if (!mounted) return;

      final travelTimes = result['travel_times'] as List? ?? [];
      final midpoint = result['midpoint'] as Map<String, dynamic>?;

      if (midpoint == null) return;

      final midLat = (midpoint['lat'] as num).toDouble();
      final midLng = (midpoint['lng'] as num).toDouble();

      final List<Map<String, dynamic>> positions = [];
      final Map<String, int> minutesMap = {};

      // 멤버 출발지 마커 (초록색) + 이동시간 수집
      for (final t in travelTimes) {
        final name = t['name'] as String? ?? '';
        final mins = (t['minutes'] as num?)?.toInt() ?? 0;
        if (name.isNotEmpty) minutesMap[name] = mins;
        if (t['lat'] == null || t['lng'] == null) continue;
        final lat = (t['lat'] as num).toDouble();
        final lng = (t['lng'] as num).toDouble();
        positions.add({'name': name, 'lat': lat, 'lng': lng});
        try {
          js.context.callMethod(
              'flutterAddCircleMarker', [lat, lng, name, '#4CAF50']);
        } catch (_) {}
      }

      final midAddress = result['address'] as String? ?? '중간 지점';

      // 중간지점 마커: 빨간 핀 + 주소 라벨
      try {
        js.context.callMethod(
            'flutterAddMidpointMarker', [midLat, midLng, midAddress]);
        js.context.callMethod('flutterFitBounds', []);
      } catch (_) {}

      if (mounted) setState(() {
        _memberPositions = positions;
        _midAddress = midAddress;
        _memberMinutes = minutesMap;
      });

      // 마커 다 추가된 후 자동 맞춤
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        js.context.callMethod('flutterFitBounds', []);
      } catch (_) {}
          } catch (e) {
            debugPrint('중간지점 로드 오류: $e');
            if (mounted) setState(() => _mapLoading = false);
          }
        }

  // ── 지도 영역 위젯 ───────────────────────────────────────────

  Widget _buildMapArea() {
    if (_mapLoading) {
      return Container(
        height: 280,
        color: const Color(0xFFF0F4FF),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 10),
              Text('지도 불러오는 중...',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    // 지도 div = 보이는 영역, 수동 좌표 추적으로 정확한 delta + 시연용 감도 부스트
    return SizedBox(
      key: _mapKey,
      height: 280,
      width: double.infinity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _lastFocalPoint = e.localPosition,
        onPointerMove: (e) {
          if (_lastFocalPoint != null) {
            final d = e.localPosition - _lastFocalPoint!;
            try {
              js.context.callMethod(
                  'flutterPanMap', [-d.dx * 12.5, -d.dy * 12.5]);
            } catch (_) {}
            _lastFocalPoint = e.localPosition;
          }
        },
        onPointerUp: (_) => _lastFocalPoint = null,
        onPointerCancel: (_) => _lastFocalPoint = null,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            try {
              js.context.callMethod('flutterZoomBy', [event.scrollDelta.dy]);
            } catch (_) {}
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  // ── 빌드 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere(
        (r) => r.id == widget.roomId,
        orElse: () => rooms.first);
    final criteria = ref.watch(searchCriteriaProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const AppHeader(title: '탐색 결과'),
      body: Column(
        children: [
          // ── 지도 영역 280px ──
          _buildMapArea(),

          // ── 결과 정보 (흰 배경) ──
          Expanded(
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          _memberPositions.isNotEmpty
                              ? '참여자 위치 기반 계산'
                              : '주소 없는 참여자 제외됨',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 8),
                    Text('중간지점: $_midAddress',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark)),
                    const SizedBox(height: 4),
                    Text('기준: ${criteria.label}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 14),
                    const Text('참여자별 소요 시간',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    ...room.members.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.success,
                                child: Text(m.name[0],
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 10),
                              Text(m.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textDark)),
                              const Spacer(),
                              Text(
                                  '${_memberMinutes[m.name] ?? m.travelMinutes ?? '-'}분',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ),

          // ── 하단 버튼 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        context.push('/room/${widget.roomId}/recommend'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textDark,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('추천 장소',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        context.push('/room/${widget.roomId}/share'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text('결과 공유',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
