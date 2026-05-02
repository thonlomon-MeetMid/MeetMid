import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/member.dart';
import '../data/models/room.dart';
import '../data/models/transport_mode.dart';
import '../data/repositories/room_repository.dart';
import 'auth_provider.dart';

final roomRepositoryProvider = Provider((ref) => RoomRepository());

final roomListProvider =
    AsyncNotifierProvider<RoomListNotifier, List<Room>>(RoomListNotifier.new);

class RoomListNotifier extends AsyncNotifier<List<Room>> {
  late final RoomRepository _repo;

  @override
  Future<List<Room>> build() async {
    _repo = ref.read(roomRepositoryProvider);
    final userId = ref.read(authProvider).user?.id ?? '';
    return _repo.fetchRoomsFromServer(userId: userId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final userId = ref.read(authProvider).user?.id ?? '';
    state = await AsyncValue.guard(() => _repo.fetchRoomsFromServer(userId: userId));
  }

  void addRoom(Room room) {
    _repo.addRoom(room);
    state = AsyncData(_repo.getRooms());
  }

  /// 서버에 방 생성 후 로컬 추가. 성공 시 Room 반환, 실패 시 null.
  Future<Room?> createRoom(
    String roomName, {
    String hostName = '',
    String hostUuid = '',
  }) async {
    final room = await _repo.createRoomOnServer(
      roomName,
      hostName: hostName,
      hostUuid: hostUuid,
    );
    if (room != null) {
      state = AsyncData(_repo.getRooms());
    }
    return room;
  }

  Future<bool> addMember(String roomId, Member member) async {
    final success = await _repo.joinRoomOnServer(
      roomId: roomId,
      name: member.name,
      address: member.departure,
      transport: member.transport.name,
    );
    if (!success) {
      _repo.addMemberToRoom(roomId, member);
    }
    state = AsyncData(_repo.getRooms());
    return success;
  }

  void removeMember(String roomId, String memberId) {
    _repo.removeMemberFromRoom(roomId, memberId);
    state = AsyncData(_repo.getRooms());
  }

  /// 서버에 강퇴 요청. 성공 시 서버 멤버 목록으로 동기화.
  Future<bool> kickMember({
    required String roomId,
    required String requesterName,
    required String targetName,
  }) async {
    final success = await _repo.kickMemberOnServer(
      roomId: roomId,
      requesterName: requesterName,
      targetName: targetName,
    );
    if (!success) {
      // 서버 실패 시 로컬에서만 제거
      _repo.removeMemberFromRoom(roomId, targetName);
    }
    state = AsyncData(_repo.getRooms());
    return success;
  }

  /// 서버에 방장 양도 요청. 성공 시 로컬 hostId 갱신.
  Future<bool> transferHost({
    required String roomId,
    required String requesterName,
    required String newHostName,
  }) async {
    final success = await _repo.transferHostOnServer(
      roomId: roomId,
      requesterName: requesterName,
      newHostName: newHostName,
    );
    if (!success) {
      // 서버 실패 시 로컬만 갱신
      final rooms = state.valueOrNull ?? [];
      final idx = rooms.indexWhere((r) => r.id == roomId);
      if (idx != -1) {
        final updated = List<Room>.from(rooms);
        updated[idx] = updated[idx].copyWith(hostId: newHostName);
        state = AsyncData(updated);
      }
    } else {
      state = AsyncData(_repo.getRooms());
    }
    return success;
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
