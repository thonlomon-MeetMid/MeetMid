import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/transport_mode.dart';
import '../../data/repositories/room_repository.dart';
import '../../data/services/api_client.dart';
import '../../providers/room_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_header.dart';

class DepartureInputScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String memberId;

  const DepartureInputScreen({
    super.key,
    required this.roomId,
    required this.memberId,
  });

  @override
  ConsumerState<DepartureInputScreen> createState() =>
      _DepartureInputScreenState();
}

class _DepartureInputScreenState extends ConsumerState<DepartureInputScreen> {
  final TextEditingController _departureController = TextEditingController();
  TransportMode _selectedTransport = TransportMode.transit;
  bool _isLoading = false;
  String _memberName = '';

  final _api = ApiClient();
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _departureController.addListener(() => setState(() {}));
    final rooms = ref.read(roomListProvider).valueOrNull ?? [];
    if (rooms.isEmpty) return;
    final room = rooms.firstWhere(
      (r) => r.id == widget.roomId,
      orElse: () => rooms.first,
    );
    final member = room.members.firstWhere(
      (m) => m.id == widget.memberId,
      orElse: () => room.members.first,
    );
    _departureController.text = member.departure;
    _selectedTransport = member.transport;
    _memberName = member.name;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _departureController.dispose();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await _api.searchPlaces(query);
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _suggestions.length,
        separatorBuilder: (context, i) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, i) {
          final place = _suggestions[i];
          return ListTile(
            dense: true,
            leading:
                const Icon(Icons.place, size: 18, color: AppColors.primary),
            title: Text(
              place['name'] as String? ?? '',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              place['address'] as String? ?? '',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            onTap: () {
              _departureController.text =
                  (place['address'] as String?)?.isNotEmpty == true
                      ? place['address'] as String
                      : place['name'] as String? ?? '';
              setState(() => _suggestions = []);
            },
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final departure = _departureController.text.trim();
    if (departure.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('출발지를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ 서버에 방 참여 요청 (출발지 포함)
      final repo = RoomRepository();
      final success = await repo.joinRoomOnServer(
        roomId: widget.roomId,
        name: _memberName,
        address: departure,
        transport: _selectedTransport.name,
      );

      // 로컬에도 업데이트
      ref.read(roomListProvider.notifier).updateMemberDeparture(
            widget.roomId,
            widget.memberId,
            departure,
            _selectedTransport,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '출발지가 저장되었습니다' : '서버 연결 실패 - 로컬에만 저장됩니다'),
            backgroundColor: success ? null : Colors.orange,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: '출발지 입력'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '출발지',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.inputBackgroundAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        const Icon(Icons.place,
                            size: 18, color: AppColors.textHint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _departureController,
                            onChanged: _onAddressChanged,
                            decoration: const InputDecoration(
                              hintText: '장소나 주소를 입력하세요 (예: 강남역)',
                              hintStyle: TextStyle(
                                  fontSize: 14, color: AppColors.textHint),
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14),
                            ),
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.textDark),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        if (_departureController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() {
                              _departureController.clear();
                              _suggestions = [];
                            }),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(Icons.cancel,
                                  size: 18, color: AppColors.textHint),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_suggestions.isNotEmpty) _buildSuggestions(),
                  const SizedBox(height: 24),
                  const Text(
                    '이동 수단',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    children: TransportMode.values
                        .map((mode) => _transportCard(mode))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : AppButton(text: '저장', onPressed: _save),
          ),
        ],
      ),
    );
  }

  Widget _transportCard(TransportMode mode) {
    final isSelected = _selectedTransport == mode;

    return GestureDetector(
      onTap: () => setState(() => _selectedTransport = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.infoBannerBg : AppColors.inputBackgroundAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _transportIcon(mode),
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(width: 8),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _transportIcon(TransportMode mode) {
    switch (mode) {
      case TransportMode.transit:
        return Icons.directions_transit;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.walk:
        return Icons.directions_walk;
      case TransportMode.bike:
        return Icons.directions_bike;
    }
  }
}