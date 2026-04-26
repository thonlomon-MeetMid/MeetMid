import '../data/models/transport_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/member.dart';
import '../data/models/room.dart';
import '../data/repositories/room_repository.dart';

final roomRepositoryProvider = Provider((ref) => RoomRepository());

final roomListProvider = StateNotifierProvider<RoomListNotifier, List<Room>>((ref) {
  final repo = ref.read(roomRepositoryProvider);
  return RoomListNotifier(repo);
});

class RoomListNotifier extends StateNotifier<List<Room>> {
  final RoomRepository _repo;

  RoomListNotifier(this._repo) : super(_repo.getRooms());

  void addRoom(Room room) {
    _repo.addRoom(room);
    state = _repo.getRooms();
  }

  void addMember(String roomId, Member member) {
    _repo.addMemberToRoom(roomId, member);
    state = _repo.getRooms();
  }

  void removeMember(String roomId, String memberId) {
    _repo.removeMemberFromRoom(roomId, memberId);
    state = _repo.getRooms();
  }

  Room? getRoomById(String id) => _repo.getRoomById(id);

  void updateMemberDeparture(
  String roomId,
  String memberId,
  String departure,
  TransportMode transport,
) {
  final rooms = state;
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

  state = updatedRooms;
}
}

