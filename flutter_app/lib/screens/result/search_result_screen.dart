// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/gestures.dart';
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
  List<Map<String, dynamic>> _memberPositions = [];
  String _midAddress = '중간 지점';


  // gesture state
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
        return;
      }
    }
    if (mounted) setState(() => _mapLoading = false);
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

      // 멤버 출발지 마커 (초록색)
      for (final t in travelTimes) {
        if (t['lat'] == null || t['lng'] == null) continue;
        final lat = (t['lat'] as num).toDouble();
        final lng = (t['lng'] as num).toDouble();
        final name = t['name'] as String? ?? '';
        positions.add({'name': name, 'lat': lat, 'lng': lng});
        try {
          js.context.callMethod(
              'flutterAddCircleMarker', [lat, lng, name, '#4CAF50']);
        } catch (_) {}
      }

      // 중간지점 마커 (빨간색)
      try {
        js.context.callMethod(
            'flutterAddCircleMarker', [midLat, midLng, '중', '#FF5252']);
        js.context.callMethod('flutterFitBounds', []);
      } catch (_) {}

      if (mounted) setState(() {
        _memberPositions = positions;
        _midAddress = result['address'] as String? ?? '중간 지점';
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

  // ── 지도 조작 헬퍼 ───────────────────────────────────────────

  void _zoomIn() {
    try {
      js.context.callMethod('flutterZoomIn', []);
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      js.context.callMethod('flutterZoomOut', []);
    } catch (_) {}
  }

  void _panMap(double dx, double dy) {
    try {
      js.context.callMethod('flutterPanMap', [-dx.toInt(), -dy.toInt()]);
    } catch (_) {}
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

    return SizedBox(
      height: 280,
      width: double.infinity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _lastFocalPoint = event.localPosition,
        onPointerMove: (event) {
          if (_lastFocalPoint != null) {
            final delta = event.localPosition - _lastFocalPoint!;
            _panMap(delta.dx, delta.dy);
            _lastFocalPoint = event.localPosition;
          }
        },
        onPointerUp: (_) => _lastFocalPoint = null,
        onPointerCancel: (_) => _lastFocalPoint = null,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 0) {
              _zoomOut();
            } else {
              _zoomIn();
            }
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
                    Text('중간지점: &_midAddress',
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
                              Text('${m.travelMinutes ?? '-'}분',
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
