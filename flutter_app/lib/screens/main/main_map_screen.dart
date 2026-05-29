import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/room_provider.dart';
import '../../data/models/room.dart';

const _kDefaultLat = 37.4508;
const _kDefaultLng = 126.6573;

class MainMapScreen extends ConsumerStatefulWidget {
  const MainMapScreen({super.key});

  @override
  ConsumerState<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends ConsumerState<MainMapScreen> {
  bool _fabExpanded = false;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _locationLoading = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 6));
        if (mounted) {
          setState(() => _currentPosition = position);
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _locationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 서비스를 켜주세요')),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('위치 권한을 허용해주세요')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('설정에서 위치 권한을 허용해주세요')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationLoading = false;
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 가져올 수 없습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  void _closeFab() {
    if (_fabExpanded) setState(() => _fabExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomListProvider).valueOrNull ?? const <Room>[];
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(_kDefaultLat, _kDefaultLng),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                  ),
                );
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // 상단 검색바
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _circleButton(
                    Icons.settings,
                    onTap: () => context.push('/settings'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _closeFab,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(23),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 14),
                            Icon(
                              Icons.search,
                              size: 18,
                              color: AppColors.textHint,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '장소 검색...',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 내 위치 버튼 + FAB
          ListenableBuilder(
            listenable: _sheetController,
            builder: (context, child) {
              double sheetPixels;
              try {
                sheetPixels = _sheetController.pixels;
              } catch (_) {
                sheetPixels = screenHeight * 0.22;
              }
              final buttonBottom = sheetPixels + 16;

              return Stack(
                children: [
                  if (_fabExpanded) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _closeFab,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: buttonBottom + 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _fabMenuItem('방 만들기', Icons.add, () {
                            _closeFab();
                            context.push('/room/create');
                          }),
                          const SizedBox(height: 8),
                          _fabMenuItem('방 찾기', Icons.search, () {
                            _closeFab();
                            context.push('/room/find');
                          }),
                          const SizedBox(height: 8),
                          _fabMenuItem('초대 참여', Icons.link, () {
                            _closeFab();
                          }),
                        ],
                      ),
                    ),
                  ],

                  Positioned(
                    left: 16,
                    bottom: buttonBottom,
                    child: _circleButton(
                      _locationLoading
                          ? Icons.hourglass_top
                          : (_currentPosition != null
                                ? Icons.my_location
                                : Icons.location_searching),
                      size: 40,
                      iconColor: _currentPosition != null
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      onTap: _locationLoading ? null : _getCurrentLocation,
                    ),
                  ),

                  Positioned(
                    right: 20,
                    bottom: buttonBottom,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _fabExpanded = !_fabExpanded),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(21),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _fabExpanded ? Icons.close : Icons.add,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // 드래그 가능한 하단 방 패널
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.22,
            minChildSize: 0.08,
            maxChildSize: 0.55,
            snap: true,
            snapSizes: const [0.08, 0.22, 0.55],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Text(
                                  '참여 중인 방',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${rooms.length}개',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                    if (rooms.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: const Icon(
                                  Icons.group_add,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '참여 중인 방이 없습니다',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => context.push('/room/create'),
                                child: const Text(
                                  '방 만들기',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _roomCard(rooms[i]),
                            ),
                            childCount: rooms.length,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _roomCard(Room room) {
    return GestureDetector(
      onTap: () => context.push('/room/${room.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(21),
              ),
              child: const Icon(
                Icons.people,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${room.memberCount}명 참여 중',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(
    IconData icon, {
    VoidCallback? onTap,
    double size = 40,
    Color iconColor = AppColors.textPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: iconColor),
      ),
    );
  }

  Widget _fabMenuItem(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
