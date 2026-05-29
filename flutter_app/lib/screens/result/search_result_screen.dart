import '../../data/models/transport_mode.dart';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/place_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common/app_header.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  final String roomId;
  const SearchResultScreen({super.key, required this.roomId});

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

const _kRouteColors = [
  Color(0xFF4CAF50),
  Color(0xFF2196F3),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFFF44336),
];

const _kMarkerColors = [
  Color(0xFF2196F3),
  Color(0xFF2196F3),
  Color(0xFF2196F3),
  Color(0xFF2196F3),
  Color(0xFF2196F3),
];

const _kMarkerBorderColors = [
  Color(0xFF1565C0),
  Color(0xFF1565C0),
  Color(0xFF1565C0),
  Color(0xFF1565C0),
  Color(0xFF1565C0),
];

const _kMarkerHues = [
  BitmapDescriptor.hueGreen,
  BitmapDescriptor.hueAzure,
  BitmapDescriptor.hueOrange,
  BitmapDescriptor.hueViolet,
  BitmapDescriptor.hueRed,
];

class _SearchResultScreenState extends ConsumerState<SearchResultScreen> {
  GoogleMapController? _mapController;
  final _api = ApiClient();
  List<Map<String, dynamic>> _memberPositions = [];
  Map<Color, BitmapDescriptor> _liveIconCache = {};
  String _midAddress = '중간 지점';
  double _midLat = 0;
  double _midLng = 0;
  Map<String, int> _memberMinutes = {};

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  bool _locationShared = false;
  Timer? _locationUpdateTimer;
  Timer? _locationPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMemberMarkers());
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _locationPollTimer?.cancel();
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
    _mapController?.dispose();
    super.dispose();
  }

  // ── 실시간 위치 공유 ──────────────────────────────────────────

  Future<void> _toggleLocation(bool value) async {
    if (value) {
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
      await _sendMyLocation();
      await _refreshLiveLocations();
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
      _removeLiveMarkers();
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

    final List<Marker> liveMarkers = [];
    for (final loc in locations) {
      final name = loc['name'] as String? ?? '';
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null || lat == 0) continue;
      final memberPos = _memberPositions.firstWhere(
        (p) => p['name'] == name,
        orElse: () => <String, dynamic>{},
      );
      final colorIndex = memberPos.isEmpty ? 0 : (memberPos['colorIndex'] as int? ?? 0);
      final memberColor = _kRouteColors[colorIndex % _kRouteColors.length];
      final liveIcon = _liveIconCache[memberColor] ??
          await _createLiveMarker(memberColor);
      _liveIconCache[memberColor] = liveIcon;
      liveMarkers.add(Marker(
        markerId: MarkerId('live_$name'),
        position: LatLng(lat, lng),
        icon: liveIcon,
        zIndex: 2,
        infoWindow: InfoWindow(title: '$name (실시간)'),
      ));
    }
    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('live_'));
      _markers.addAll(liveMarkers);
    });
  }

  void _removeLiveMarkers() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('live_'));
    });
  }

  // ── 지도 마커/폴리라인 로드 ────────────────────────────────────

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

      final newMarkers = <Marker>{};
      final newPolylines = <Polyline>{};
      final List<Map<String, dynamic>> positions = [];
      final Map<String, int> minutesMap = {};

      for (int i = 0; i < travelTimes.length; i++) {
        final t = travelTimes[i];
        final name = t['name'] as String? ?? '';
        final mins = (t['minutes'] as num?)?.toInt() ?? 0;
        if (name.isNotEmpty) minutesMap[name] = mins;
        if (t['lat'] == null || t['lng'] == null) continue;
        final lat = (t['lat'] as num).toDouble();
        final lng = (t['lng'] as num).toDouble();
        positions.add({'name': name, 'lat': lat, 'lng': lng, 'colorIndex': i});
        final icon = await _createPinMarker(
          _kMarkerColors[i % _kMarkerColors.length],
          _kMarkerBorderColors[i % _kMarkerBorderColors.length],
        );
        newMarkers.add(
          Marker(
            markerId: MarkerId('member_$name'),
            position: LatLng(lat, lng),
            icon: icon,
            zIndex: 1,
            infoWindow: InfoWindow(title: name, snippet: '$mins분'),
          ),
        );
      }

      var midAddress = result['address'] as String? ?? '중간 지점';
      var destLat = midLat;
      var destLng = midLng;

      // ── 카테고리 선택 시: Places API → 1순위 장소를 목적지로 사전 결정 ──
      final categoryCode = ref.read(selectedCategoryCodeProvider);
      if (categoryCode.isNotEmpty) {
        try {
          final autoPlaces = await _api.getPlaceRecommendations(
            roomId: widget.roomId,
            categoryCode: categoryCode,
            lat: midLat,
            lng: midLng,
            radius: 500,
            size: 1,
          );
          if (autoPlaces.isNotEmpty &&
              autoPlaces.first.lat != 0 &&
              autoPlaces.first.lng != 0) {
            final p = autoPlaces.first;
            destLat = p.lat;
            destLng = p.lng;
            midAddress = p.name;

            // 선택 장소 기준 소요시간 + 폴리라인 재계산 (1회 추가 호출)
            try {
              final overr = await _api.getMidpoint(
                widget.roomId,
                criteria: criteria.name,
                polyline: true,
                overrideLat: destLat,
                overrideLng: destLng,
              );
              final rawOvPoly = overr['polylines'] as List?;
              if (rawOvPoly != null) {
                newPolylines.clear();
                for (int i = 0; i < rawOvPoly.length; i++) {
                  final rp = rawOvPoly[i] as Map<String, dynamic>;
                  final rn = rp['name'] as String? ?? 'route_$i';
                  final pts = (rp['coords'] as List? ?? []).map((c) {
                    final pair = c as List;
                    return LatLng((pair[1] as num).toDouble(),
                        (pair[0] as num).toDouble());
                  }).toList();
                  if (pts.length >= 2) {
                    newPolylines.add(Polyline(
                      polylineId: PolylineId('route_$rn'),
                      points: pts,
                      color: _kRouteColors[i % _kRouteColors.length],
                      width: 4,
                    ));
                  }
                }
              }
              for (final t in (overr['travel_times'] as List? ?? [])) {
                final n = t['name'] as String? ?? '';
                final m = (t['minutes'] as num?)?.toInt() ?? 0;
                if (n.isNotEmpty) minutesMap[n] = m;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      // 폴리라인 (카테고리 미선택이면 원래 응답 그대로 사용)
      if (newPolylines.isEmpty) {
        final rawPolylines = result['polylines'] as List?;
        if (rawPolylines != null) {
          for (int i = 0; i < rawPolylines.length; i++) {
            final p = rawPolylines[i] as Map<String, dynamic>;
            final name = p['name'] as String? ?? 'route_$i';
            final coords = p['coords'] as List? ?? [];
            final points = coords.map((c) {
              final pair = c as List;
              return LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              );
            }).toList();
            if (points.length >= 2) {
              newPolylines.add(Polyline(
                polylineId: PolylineId('route_$name'),
                points: points,
                color: _kRouteColors[i % _kRouteColors.length],
                width: 4,
              ));
            }
          }
        }
      }

      // 깃발 마커는 최종 목적지(destLat/destLng) 기준
      newMarkers.add(Marker(
        markerId: const MarkerId('midpoint'),
        position: LatLng(destLat, destLng),
        icon: await _createFlagMarker(
          const Color(0xFFEB3B5A),
          const Color(0xFFC0392B),
        ),
        zIndex: 3,
        infoWindow: InfoWindow(title: midAddress),
      ));

      if (mounted) {
        // provider에도 반영 → place_recommend_screen이 올바른 좌표로 API 호출
        ref.read(midpointLatProvider.notifier).state = destLat;
        ref.read(midpointLngProvider.notifier).state = destLng;
        setState(() {
          _markers = newMarkers;
          _polylines = newPolylines;
          _memberPositions = positions;
          _midAddress = midAddress;
          _memberMinutes = minutesMap;
          _midLat = destLat;
          _midLng = destLng;
        });
        _fitBounds(newMarkers);
      }
    } catch (e) {
      debugPrint('중간지점 로드 오류: $e');
    }
  }

  // ── 장소 선택 적용: 마커·폴리라인·소요시간 일괄 갱신 ──
  Future<void> _applyPlace(String name, double lat, double lng) async {
    final flagIcon = await _createFlagMarker(
        const Color(0xFFEB3B5A), const Color(0xFFC0392B));
    if (!mounted) return;

    // provider에도 반영 → place_recommend_screen이 올바른 좌표로 API 호출
    ref.read(midpointLatProvider.notifier).state = lat;
    ref.read(midpointLngProvider.notifier).state = lng;
    setState(() {
      _midLat = lat;
      _midLng = lng;
      _midAddress = name.isNotEmpty ? name : '선택된 장소';
      _markers.removeWhere((m) => m.markerId.value == 'midpoint');
      _markers.add(Marker(
        markerId: const MarkerId('midpoint'),
        position: LatLng(lat, lng),
        icon: flagIcon,
        zIndex: 3,
        infoWindow: InfoWindow(title: _midAddress),
      ));
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));

    // 선택 장소 기준 소요시간 + 폴리라인 재계산
    try {
      final criteria = ref.read(searchCriteriaProvider);
      final r = await _api.getMidpoint(
        widget.roomId,
        criteria: criteria.name,
        polyline: true,
        overrideLat: lat,
        overrideLng: lng,
      );
      if (!mounted) return;

      // 폴리라인 갱신
      final rawPolylines = r['polylines'] as List?;
      final newPolylines = <Polyline>{};
      if (rawPolylines != null) {
        for (int i = 0; i < rawPolylines.length; i++) {
          final p = rawPolylines[i] as Map<String, dynamic>;
          final pName = p['name'] as String? ?? 'route_$i';
          final coords = p['coords'] as List? ?? [];
          final points = coords.map((c) {
            final pair = c as List;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          }).toList();
          if (points.length >= 2) {
            newPolylines.add(Polyline(
              polylineId: PolylineId('route_$pName'),
              points: points,
              color: _kRouteColors[i % _kRouteColors.length],
              width: 4,
            ));
          }
        }
      }

      // 소요시간 갱신
      final travelTimes = r['travel_times'] as List? ?? [];
      final minutesMap = <String, int>{};
      for (final t in travelTimes) {
        final n = t['name'] as String? ?? '';
        final m = (t['minutes'] as num?)?.toInt() ?? 0;
        if (n.isNotEmpty) minutesMap[n] = m;
      }

      if (!mounted) return;
      setState(() {
        _polylines = newPolylines;
        _memberMinutes = minutesMap;
      });
      _fitBounds({..._markers});
    } catch (e) {
      debugPrint('장소 적용 오류: $e');
    }
  }



  // ── 장소 추천 화면 열기 → 결과 받아 적용 ──
  Future<void> _openRecommend(BuildContext ctx) async {
    final result = await ctx.push<Map<String, dynamic>?>(
        '/room/${widget.roomId}/recommend');
    if (!mounted || result == null) return;

    final name = result['name'] as String? ?? '';
    final lat = (result['lat'] as num?)?.toDouble() ?? _midLat;
    final lng = (result['lng'] as num?)?.toDouble() ?? _midLng;
    await _applyPlace(name, lat, lng);
  }

  void _fitBounds(Set<Marker> markers) {
    if (_mapController == null || markers.isEmpty) return;
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final m in markers) {
      final lat = m.position.latitude;
      final lng = m.position.longitude;
      minLat = min(minLat, lat);
      maxLat = max(maxLat, lat);
      minLng = min(minLng, lng);
      maxLng = max(maxLng, lng);
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  Color _memberColor(String name) {
    final pos = _memberPositions.firstWhere(
      (p) => p['name'] == name,
      orElse: () => <String, dynamic>{},
    );
    if (pos.isEmpty) return AppColors.success;
    final idx = (pos['colorIndex'] as int? ?? 0) % _kRouteColors.length;
    return _kRouteColors[idx];
  }

  Future<BitmapDescriptor> _createPinMarker(Color color, Color borderColor) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 80.0;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final polePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;

    // 막대기 테두리
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size/2 - 5, size/2, 10, size/2 - 4), const Radius.circular(4)),
      borderPaint,
    );
    // 막대기 내부 (어두운 회색)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size/2 - 2.5, size/2, 5, size/2 - 6), const Radius.circular(3)),
      polePaint,
    );

    // 동그라미 테두리
    canvas.drawCircle(Offset(size/2, size/2.8), 22, borderPaint);
    // 동그라미 내부
    canvas.drawCircle(Offset(size/2, size/2.8), 18, fillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createLiveMarker([Color color = const Color(0xFF26DE81)]) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 120.0;

    // 그라데이션 퍼지는 큰 원
    final gradientPaint = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(size/2, size/2),
        size/2,
        [
          color.withOpacity(0.7),
          color.withOpacity(0.0),
        ],
      );
    canvas.drawCircle(const Offset(size/2, size/2), size/2, gradientPaint);

    // 흰 테두리 원
    canvas.drawCircle(const Offset(size/2, size/2), size/6, Paint()..color = Colors.white..style = PaintingStyle.fill);

    // 내부 색상 원
    canvas.drawCircle(const Offset(size/2, size/2), size/7, Paint()..color = color..style = PaintingStyle.fill);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createFlagMarker(Color color, Color borderColor) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const width = 120.0;
    const height = 100.0;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final polePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;

    // 깃대
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(width/2 - 4, 4, 8, height - 8), const Radius.circular(4)),
      borderPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(width/2 - 2, 4, 4, height - 8), const Radius.circular(2)),
      polePaint,
    );

    // 깃발 삼각형 테두리
    final flagBorderPath = Path();
    flagBorderPath.moveTo(width/2 - 3, 4);
    flagBorderPath.lineTo(width - 6, 32);
    flagBorderPath.lineTo(width/2 - 3, 60);
    canvas.drawPath(flagBorderPath, borderPaint);

    // 깃발 삼각형 내부
    final flagPath = Path();
    flagPath.moveTo(width/2 + 2, 9);
    flagPath.lineTo(width - 12, 32);
    flagPath.lineTo(width/2 + 2, 55);
    canvas.drawPath(flagPath, fillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
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
        'kakaomap://route?sp=${member['lat']},${member['lng']}&ep=$_midLat,$_midLng&by=PUBLICTRANSIT';
    final kakaoWebUrl =
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
                      final appUrl = Uri.parse(kakaoUrl);
                      final webUrl = Uri.parse(kakaoWebUrl);
                      if (await canLaunchUrl(appUrl)) {
                        await launchUrl(appUrl);
                      } else {
                        await launchUrl(
                          webUrl,
                          mode: LaunchMode.platformDefault,
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
      appBar: AppHeader(title: '탐색 결과', onBack: () => context.pop()),
      body: Column(
        children: [
          // ── 지도 영역 280px ──
          SizedBox(
            height: 280,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _midLat != 0
                    ? LatLng(_midLat, _midLng)
                    : const LatLng(37.5665, 126.9780),
                zoom: 12,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                Future.delayed(const Duration(milliseconds: 1500), () {
                  controller.showMarkerInfoWindow(const MarkerId('midpoint'));
                  if (_markers.isNotEmpty) {
                    _fitBounds(_markers);
                  }
                });
              },
              markers: _markers,
              polylines: _polylines,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
            ),
          ),

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
                      style: const TextStyle(
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
                              backgroundColor: _memberColor(m.name),
                              child: Text(
                                m.name.isNotEmpty ? m.name[0] : '?',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Row(
                              children: [
                                Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  m.transport == TransportMode.transit
                                      ? Icons.directions_transit
                                      : m.transport == TransportMode.car
                                          ? Icons.directions_car
                                          : m.transport == TransportMode.walk
                                              ? Icons.directions_walk
                                              : Icons.directions_bike,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                            const Spacer(),
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
                                const SizedBox(width: 8),
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
                                      borderRadius: BorderRadius.circular(8),
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
                onPressed: () => _openRecommend(context),
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
