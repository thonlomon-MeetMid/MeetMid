import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/member.dart';
import '../data/models/room.dart';
import '../data/models/transport_mode.dart';
import '../data/repositories/room_repository.dart';

final roomRepositoryProvider = Provider((ref) => RoomRepository());

final roomListProvider =
    AsyncNotifierProvider<RoomListNotifier, List<Room>>(RoomListNotifier.new);

class RoomListNotifier extends AsyncNotifier<List<Room>> {
  late final RoomRepository _repo;

  @override
  Future<List<Room>> build() async {
    _repo = ref.read(roomRepositoryProvider);
    return _repo.fetchRoomsFromServer();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchRoomsFromServer());
  }

  void addRoom(Room room) {
    _repo.addRoom(room);
    state = AsyncData(_repo.getRooms());
  }

  Future<bool> addMember(String roomId, Member member) async {
    final success = await _repo.joinRoomOnServer(
      roomId: roomId,
      name: member.name,
      address: member.departure,
      transport: member.transport.name,
    );
    if (!success) {
      // 서버 실패 시 로컬에만 추가
      _repo.addMemberToRoom(roomId, member);
    }
    state = AsyncData(_repo.getRooms());
    return success;
  }

  void removeMember(String roomId, String memberId) {
    _repo.removeMemberFromRoom(roomId, memberId);
    state = AsyncData(_repo.getRooms());
  }

  Room? getRoomById(String id) => _repo.getRoomById(id);

  void updateMemberDeparture(
    String roomId,
    String memberId,
    String departure,
    TransportMode transport,
  ) {
    final rooms = state.valueOrNull ?? [];
    final roomIndex = rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) return;

    final room = rooms[roomIndex];
    final memberIndex = room.members.indexWhere((m) => m.id == memberId);
    if (memberIndex == -1) return;

    final updatedMember = room.members[memberIndex].copyWith(
      departure: departure,
      transport: transport,
    );
    final updatedMembers = List<Member>.from(room.members);
    updatedMembers[memberIndex] = updatedMember;

    final updatedRoom = room.copyWith(members: updatedMembers);
    final updatedRooms = List<Room>.from(rooms);
    updatedRooms[roomIndex] = updatedRoom;

    state = AsyncData(updatedRooms);
  }
}
