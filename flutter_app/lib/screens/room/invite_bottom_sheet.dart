import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'add_member_dialog.dart';

class InviteBottomSheet extends StatefulWidget {
  final String roomId;
  const InviteBottomSheet({super.key, required this.roomId});

  @override
  State<InviteBottomSheet> createState() => _InviteBottomSheetState();
}

class _InviteBottomSheetState extends State<InviteBottomSheet> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 12),

          const Text('방 초대 / 직접 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 16),

          // 탭
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _tab('링크 초대', 0),
                const SizedBox(width: 24),
                _tab('직접 추가', 1),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // 콘텐츠
          Expanded(
            child: _tabIndex == 0 ? _linkTab() : _addTab(context),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 2, width: 60, color: selected ? AppColors.primary : Colors.transparent),
        ],
      ),
    );
  }

  Widget _linkTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('초대 링크', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('meetmid.com/invite/abc123', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
                GestureDetector(
                  onTap: () {},
                  child: const Icon(Icons.copy, size: 18, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.share, size: 18),
              label: const Text('링크 공유'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTab(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (_) => AddMemberDialog(roomId: widget.roomId),
          );
        },
        icon: const Icon(Icons.person_add, size: 18),
        label: const Text('참여자 추가'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
