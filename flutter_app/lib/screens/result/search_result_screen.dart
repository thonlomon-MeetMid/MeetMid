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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한을 허용해주세요')),
          );
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
    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('live_'));
      for (final loc in locations) {
        final name = loc['name'] as String? ?? '';
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat == null || lng == null || lat == 0) continue;
        _markers.add(
          Marker(
            markerId: MarkerId('live_$name'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueCyan,
            ),
            infoWindow: InfoWindow(title: '$name (실시간)'),
          ),
        );
      }
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
        newMarkers.add(
          Marker(
            markerId: MarkerId('member_$name'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _kMarkerHues[i % _kMarkerHues.length],
            ),
            infoWindow: InfoWindow(title: name, snippet: '$mins분'),
          ),
        );
      }

      final midAddress = result['address'] as String? ?? '중간 지점';
      newMarkers.add(
        Marker(
          markerId: const MarkerId('midpoint'),
          position: LatLng(midLat, midLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          infoWindow: InfoWindow(title: midAddress),
        ),
      );

      final rawPolylines = result['polylines'] as List?;
      if (rawPolylines != null) {
        for (int i = 0; i < rawPolylines.length; i++) {
          final p = rawPolylines[i] as Map<String, dynamic>;
          final name = p['name'] as String? ?? 'route_$i';
          final coords = p['coords'] as List? ?? [];
          final points = coords
              .map((c) {
                final pair = c as List;
                // coords are [lng, lat] from backend
                return LatLng(
                  (pair[1] as num).toDouble(),
                  (pair[0] as num).toDouble(),
                );
              })
              .toList();
          if (points.length >= 2) {
            newPolylines.add(
              Polyline(
                polylineId: PolylineId('route_$name'),
                points: points,
                color: _kRouteColors[i % _kRouteColors.length],
                width: 4,
              ),
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _markers = newMarkers;
          _polylines = newPolylines;
          _memberPositions = positions;
          _midAddress = midAddress;
          _memberMinutes = minutesMap;
        });
        _fitBounds(newMarkers);
      }
    } catch (e) {
      debugPrint('중간지점 로드 오류: $e');
    }
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
      appBar: AppHeader(
        title: '탐색 결과',
        onBack: () => context.pop(),
      ),
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
                if (_markers.isNotEmpty) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _fitBounds(_markers);
                  });
                }
              },
              markers: _markers,
              polylines: _polylines,
              zoomControlsEnabled: false,
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
