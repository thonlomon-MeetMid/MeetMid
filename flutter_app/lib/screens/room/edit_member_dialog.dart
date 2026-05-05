import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/member.dart';
import '../../data/models/transport_mode.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';

class EditMemberDialog extends ConsumerStatefulWidget {
  final String roomId;
  final Member member;

  const EditMemberDialog({
    super.key,
    required this.roomId,
    required this.member,
  });

  @override
  ConsumerState<EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends ConsumerState<EditMemberDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _departureCtrl;
  late TransportMode _transport;
  bool _isLoading = false;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.member.name);
    _departureCtrl = TextEditingController(text: widget.member.departure);
    _transport = widget.member.transport;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _departureCtrl.dispose();
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

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    setState(() => _isLoading = true);

    final requesterName = ref.read(authProvider).user?.name ?? '';
    final success = await ref.read(roomListProvider.notifier).updateMemberInfo(
          roomId: widget.roomId,
          requesterName: requesterName,
          oldName: widget.member.name,
          newName: newName,
          address: _departureCtrl.text.trim(),
          transport: _transport.name,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? '정보가 변경되었습니다' : '정보 변경에 실패했습니다'),
      backgroundColor: success ? null : Colors.orange,
    ));
    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '참여자 정보 변경',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark),
            ),
            const SizedBox(height: 20),

            _labeledField('이름', '예: 홍길동', _nameCtrl),
            const SizedBox(height: 12),

            // ── 출발지 with live search ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('출발지',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.place,
                          size: 16, color: AppColors.textHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _departureCtrl,
                          onChanged: _onAddressChanged,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: '주소 검색',
                            hintStyle:
                                TextStyle(color: AppColors.textHint),
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_departureCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() {
                            _departureCtrl.clear();
                            _suggestions = [];
                          }),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.cancel,
                                size: 16, color: AppColors.textHint),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 180),
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
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final place = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place,
                              size: 16, color: AppColors.primary),
                          title: Text(
                            place['name'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            place['address'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                          onTap: () {
                            final addr =
                                (place['address'] as String?)?.isNotEmpty ==
                                        true
                                    ? place['address'] as String
                                    : place['name'] as String? ?? '';
                            setState(() {
                              _departureCtrl.text = addr;
                              _suggestions = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 이동수단 ──
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('이동수단',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _transportButton(
                        Icons.directions_transit,
                        '대중교통',
                        TransportMode.transit)),
                const SizedBox(width: 8),
                Expanded(
                    child: _transportButton(
                        Icons.directions_car, '자동차', TransportMode.car)),
              ],
            ),
            const SizedBox(height: 24),

            // ── 하단 버튼 ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderLight),
                      foregroundColor: AppColors.textSecondary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('취소',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('저장',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transportButton(IconData icon, String label, TransportMode mode) {
    final isSelected = _transport == mode;
    return GestureDetector(
      onTap: () => setState(() => _transport = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 28,
                color:
                    isSelected ? Colors.white : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textDark)),
          ],
        ),
      ),
    );
  }

  Widget _labeledField(
      String label, String hint, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.inputBackground,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
