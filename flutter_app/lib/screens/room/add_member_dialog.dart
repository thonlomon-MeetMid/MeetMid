import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/member.dart';
import '../../data/models/transport_mode.dart';
import '../../providers/room_provider.dart';

class AddMemberDialog extends ConsumerStatefulWidget {
  final String roomId;
  const AddMemberDialog({super.key, required this.roomId});

  @override
  ConsumerState<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<AddMemberDialog> {
  final _nameCtrl = TextEditingController();
  final _departureCtrl = TextEditingController();
  TransportMode _transport = TransportMode.transit;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _departureCtrl.dispose();
    super.dispose();
  }

  void _add() {
    if (_nameCtrl.text.isEmpty) return;
    final member = Member(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text,
      departure: _departureCtrl.text,
      transport: _transport,
    );
    ref.read(roomListProvider.notifier).addMember(widget.roomId, member);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('참여자 직접 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 16),

            _field('이름', '이름을 입력하세요', _nameCtrl),
            const SizedBox(height: 12),
            _field('출발지', '출발 장소를 입력하세요', _departureCtrl),
            const SizedBox(height: 16),

            const Text('이동 수단', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Row(
              children: TransportMode.values.map((t) {
                final selected = _transport == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _transport = t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _icon(t),
                            size: 18,
                            color: selected ? Colors.white : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.label,
                            style: TextStyle(fontSize: 10, color: selected ? Colors.white : AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _add,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('추가'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String hint, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.inputBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  IconData _icon(TransportMode t) {
    switch (t) {
      case TransportMode.transit: return Icons.directions_transit;
      case TransportMode.car: return Icons.directions_car;
      case TransportMode.walk: return Icons.directions_walk;
      case TransportMode.bike: return Icons.directions_bike;
    }
  }
}
