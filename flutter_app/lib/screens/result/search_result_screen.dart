// ignore: avoid_web_libraries_in_flutter
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_header.dart';
import 'package:flutter/services.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  final String roomId;
  const SearchResultScreen({super.key, required this.roomId});

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

// 참여자별 경로 색상 (마커 색상과 동일하게 순환)
const _kRouteColors = ['#4CAF50', '#2196F3', '#FF9800', '#9C27B0', '#F44336'];

class _SearchResultScreenState extends ConsumerState<SearchResultScreen> {
  bool _mapLoading = true;
  bool _mapInitStarted = false;
  final _api = ApiClient();
  final _mapKey = GlobalKey();
  List<Map<String, dynamic>> _memberPositions = [];
  String _midAddress = '중간 지점';
  double _midLat = 0;
  double _midLng = 0;
  Map<String, int> _memberMinutes = {};
  Offset? _lastFocalPoint;

  // 실시간 위치 공유
  bool _locationShared = false;
  Timer? _locationUpdateTimer;
  Timer? _locationPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMapInit());
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _locationPollTimer?.cancel();
    // 화면 떠날 때 위치 공유 해제
    if (_locationShared) {
      final user = ref.read(authProvider).user;
      _api.updateLocation(
        roomId: widget.roomId,
        memberName: user?.name ?? '',
        lat: 0,
        lng: 0,
        shared: false,
      );
    }
    // 방장이 나가면 탐색 상태 초기화
    final rooms = ref.read(roomListProvider).valueOrNull ?? [];
    if (rooms.isNotEmpty) {
      final room = rooms.firstWhere(
        (r) => r.id == widget.roomId,
        orElse: () => rooms.first,
      );
      final currentUserName = ref.read(authProvider).user?.name ?? '';
      if (room.hostId == currentUserName) {
        _api.startSearch(widget.roomId, 'reset');
      }
    }
    try {
      js.context.callMethod('flutterDestroyKakaoMap', []);
    } catch (_) {}
    try {
      js.context.callMethod('flutterDestroyKakaoMap', []);
    } catch (_) {}
    super.dispose();
  }

  // ── 실시간 위치 공유 ──────────────────────────────────────────

  Future<void> _toggleLocation(bool value) async {
    if (value) {
      // 권한 확인
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('위치 권한을 허용해주세요')));
        }
        return;
      }
      setState(() => _locationShared = true);
      // 위치 전송 후 즉시 지도 반영
      await _sendMyLocation();
      await _refreshLiveLocations();
      // 8초마다 내 위치 갱신, 2초마다 전체 폴링
      _locationUpdateTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => _sendMyLocation(),
      );
      _locationPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshLiveLocations(),
      );
    } else {
      setState(() => _locationShared = false);
      _locationUpdateTimer?.cancel();
      _locationPollTimer?.cancel();
      final user = ref.read(authProvider).user;
      await _api.updateLocation(
        roomId: widget.roomId,
        memberName: user?.name ?? '',
        lat: 0,
        lng: 0,
        shared: false,
      );
      // 지도에서 내 위치 점 제거
      try {
        js.context.callMethod('flutterSetLiveLocations', ['[]']);
      } catch (_) {}
    }
  }

  Future<void> _sendMyLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final user = ref.read(authProvider).user;
      await _api.updateLocation(
        roomId: widget.roomId,
        memberName: user?.name ?? '',
        lat: position.latitude,
        lng: position.longitude,
        shared: true,
      );
    } catch (_) {}
  }

  Future<void> _refreshLiveLocations() async {
    final locations = await _api.getLiveLocations(widget.roomId);
    if (!mounted) return;
    try {
      js.context.callMethod('flutterSetLiveLocations', [jsonEncode(locations)]);
    } catch (_) {}
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
      js.context.callMethod('flutterSetMapBounds', [
        topLeft.dy,
        topLeft.dx,
        size.width,
        size.height,
      ]);
    } catch (_) {}
  }

  void _showRouteOptions(BuildContext context, String memberName) {
    final member = _memberPositions.firstWhere(
      (m) => m['name'] == memberName,
      orElse: () => {},
    );
    if (member.isEmpty) return;

    final rooms = ref.read(roomListProvider).valueOrNull ?? [];
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final departure = room.members
        .firstWhere(
          (m) => m.name == memberName,
          orElse: () => room.members.first,
        )
        .departure;
    final kakaoUrl =
        'https://map.kakao.com/link/from/$departure,${member['lat']},${member['lng']}/to/$_midAddress,$_midLat,$_midLng';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '$memberName님 맞춤 길찾기',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    leading: const Icon(Icons.map, color: AppColors.primary),
                    title: const Text(
                      '카카오맵으로 길찾기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final url = Uri.parse(kakaoUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    leading: const Icon(Icons.copy, color: AppColors.primary),
                    title: const Text(
                      '링크 복사',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await Clipboard.setData(ClipboardData(text: kakaoUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('링크가 복사됐어요!')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openKakaoMap(String memberName) async {
    final member = _memberPositions.firstWhere(
      (m) => m['name'] == memberName,
      orElse: () => {},
    );
    if (member.isEmpty) return;

    final srcLat = member['lat'];
    final srcLng = member['lng'];
    final dstLat = _midLat;
    final dstLng = _midLng;

    final rooms = ref.read(roomListProvider).valueOrNull ?? [];
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final departure = room.members
        .firstWhere(
          (m) => m.name == memberName,
          orElse: () => room.members.first,
        )
        .departure;

    final url = Uri.parse(
      'https://map.kakao.com/link/from/$departure,$srcLat,$srcLng/to/$_midAddress,$dstLat,$dstLng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _loadMemberMarkers() async {
    final criteria = ref.read(searchCriteriaProvider);
    try {
      final result = await _api.getMidpoint(
        widget.roomId,
        criteria: criteria.name,
        polyline: true,
      );

      if (!mounted) return;

      final travelTimes = result['travel_times'] as List? ?? [];
      final midpoint = result['midpoint'] as Map<String, dynamic>?;

      if (midpoint == null) return;

      final midLat = (midpoint['lat'] as num).toDouble();
      final midLng = (midpoint['lng'] as num).toDouble();
      _midLat = midLat;
      _midLng = midLng;

      final List<Map<String, dynamic>> positions = [];
      final Map<String, int> minutesMap = {};

      // 멤버 출발지 마커 (참여자별 색상) + 이동시간 수집
      for (int i = 0; i < travelTimes.length; i++) {
        final t = travelTimes[i];
        final name = t['name'] as String? ?? '';
        final mins = (t['minutes'] as num?)?.toInt() ?? 0;
        final color = _kRouteColors[i % _kRouteColors.length];
        if (name.isNotEmpty) minutesMap[name] = mins;
        if (t['lat'] == null || t['lng'] == null) continue;
        final lat = (t['lat'] as num).toDouble();
        final lng = (t['lng'] as num).toDouble();
        positions.add({'name': name, 'lat': lat, 'lng': lng, 'color': color});
        try {
          js.context.callMethod('flutterAddCircleMarker', [
            lat,
            lng,
            name,
            color,
          ]);
        } catch (_) {}
      }

      final midAddress = result['address'] as String? ?? '중간 지점';

      // 중간지점 마커 + fitBounds
      try {
        js.context.callMethod('flutterAddMidpointMarker', [
          midLat,
          midLng,
          midAddress,
        ]);
        js.context.callMethod('flutterFitBounds', []);
      } catch (_) {}

      // 경로 polyline 그리기
      final rawPolylines = result['polylines'] as List?;
      if (rawPolylines != null && rawPolylines.isNotEmpty) {
        final polylineData = <Map<String, dynamic>>[];
        for (int i = 0; i < rawPolylines.length; i++) {
          final p = rawPolylines[i] as Map<String, dynamic>;
          polylineData.add({
            'name': p['name'],
            'coords': p['coords'],
            'color': _kRouteColors[i % _kRouteColors.length],
          });
        }
        try {
          js.context.callMethod('flutterDrawPolylines', [
            jsonEncode(polylineData),
          ]);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _memberPositions = positions;
          _midAddress = midAddress;
          _midAddress = midAddress;
          double _midLat = 0;
          double _midLng = 0;
          _midLat = midLat;
          _midLng = midLng;
          _memberMinutes = minutesMap;
        });
      }

      // 마커 + polyline 다 추가된 후 자동 맞춤
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
              Text(
                '지도 불러오는 중...',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      key: _mapKey,
      height: 280,
      width: double.infinity,
      child: Stack(
        children: [
          // 지도 인터랙션 레이어
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _lastFocalPoint = e.localPosition,
            onPointerMove: (e) {
              if (_lastFocalPoint != null) {
                final d = e.localPosition - _lastFocalPoint!;
                try {
                  js.context.callMethod('flutterPanMap', [
                    -d.dx * 12.5,
                    -d.dy * 12.5,
                  ]);
                } catch (_) {}
                _lastFocalPoint = e.localPosition;
              }
            },
            onPointerUp: (_) => _lastFocalPoint = null,
            onPointerCancel: (_) => _lastFocalPoint = null,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                try {
                  js.context.callMethod('flutterZoomBy', [
                    event.scrollDelta.dy,
                  ]);
                } catch (_) {}
              }
            },
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }

  // ── 빌드 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final criteria = ref.watch(searchCriteriaProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppHeader(
        title: '탐색 결과',
        onBack: () {
          try {
            js.context.callMethod('flutterDestroyKakaoMap', []);
            js.context['_kakaoMapReady'] = false;
            js.context['_kakaoMapCancelled'] = false;
            // 메인 화면 지도 재생성
            Future.delayed(const Duration(milliseconds: 300), () {
              js.context.callMethod('flutterCreateKakaoMapInBody', [
                37.4508,
                126.6573,
              ]);
            });
          } catch (_) {}
          context.pop();
        },
      ),
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
                        const Icon(
                          Icons.my_location,
                          size: 16,
                          color: Color(0xFF26DE81),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '내 위치 공유',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF26DE81),
                          ),
                        ),
                        const Spacer(),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: _locationShared,
                            onChanged: _toggleLocation,
                            activeTrackColor: const Color(0xFF20BF6B),
                            thumbColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFF26DE81);
                              }
                              return null;
                            }),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 8),
                    Text(
                      '중간지점: $_midAddress',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '기준: ${criteria.label}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '참여자별 소요 시간',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...room.members.map(
                      (m) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.success,
                              child: Text(
                                m.name[0],
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              m.name,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_memberMinutes[m.name] ?? m.travelMinutes ?? '-'}분',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () =>
                                          _showRouteOptions(context, m.name),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          '길찾기',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(width: 8),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 하단 버튼 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    context.push('/room/${widget.roomId}/recommend'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '추천 장소',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
