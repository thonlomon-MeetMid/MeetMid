import '../models/member.dart';
import '../models/room.dart';
import '../models/transport_mode.dart';
import '../services/api_client.dart';

class RoomRepository {
  final ApiClient _apiClient = ApiClient();

  final List<Room> _rooms = [];

  List<Room> getRooms() => List.unmodifiable(_rooms);

  Room? getRoomById(String id) {
    try {
      return _rooms.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  void addRoom(Room room) {
    _rooms.add(room);
  }

  void addMemberToRoom(String roomId, Member member) {
    final index = _rooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      final room = _rooms[index];
      final updatedMembers = [...room.members, member];
      _rooms[index] = room.copyWith(
        members: updatedMembers,
        memberCount: updatedMembers.length,
      );
    }
  }

  void removeMemberFromRoom(String roomId, String memberId) {
    final index = _rooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      final room = _rooms[index];
      final updatedMembers = room.members.where((m) => m.id != memberId).toList();
      _rooms[index] = room.copyWith(
        members: updatedMembers,
        memberCount: updatedMembers.length,
      );
    }
  }

  // 서버에서 방 목록을 가져와 로컬 캐시(_rooms)에 저장
  Future<List<Room>> fetchRoomsFromServer() async {
    final data = await _apiClient.getRooms();
    final fetched = data.map((d) {
      final serverMembers = (d['members'] as List<dynamic>).map((m) {
        return Member(
          id: m['name'] as String,
          name: m['name'] as String,
          departure: m['address'] as String,
          transport: TransportMode.values.firstWhere(
            (t) => t.name == (m['transport'] as String),
            orElse: () => TransportMode.transit,
          ),
        );
      }).toList();
      return Room(
        id: d['room_id'] as String,
        name: d['room_name'] as String,
        memberCount: serverMembers.length,
        members: serverMembers,
      );
    }).toList();
    _rooms
      ..clear()
      ..addAll(fetched);
    return List.unmodifiable(_rooms);
  }

  // 서버에 방 만들기
  Future<Room?> createRoomOnServer(String roomName) async {
    try {
      final data = await _apiClient.createRoom(roomName);
      final room = Room(
        id: data['room_id'] as String,
        name: data['room_name'] as String,
        memberCount: 0,
        members: [],
      );
      _rooms.add(room);
      return room;
    } catch (e) {
      // ignore: avoid_print
      print('[createRoomOnServer] 서버 오류: $e');
      return null;
    }
  }

  // 서버에 방 참여 (출발지 포함)
  Future<bool> joinRoomOnServer({
    required String roomId,
    required String name,
    required String address,
    required String transport,
  }) async {
    try {
      final data = await _apiClient.joinRoom(
        roomId: roomId,
        name: name,
        address: address,
        transport: transport,
      );
      if (data['ok'] == true) {
        final serverMembers = (data['members'] as List).map((m) {
          return Member(
            id: m['name'] as String,
            name: m['name'] as String,
            departure: m['address'] as String,
            transport: TransportMode.values.firstWhere(
              (t) => t.name == m['transport'],
              orElse: () => TransportMode.transit,
            ),
          );
        }).toList();

        final index = _rooms.indexWhere((r) => r.id == roomId);
        if (index != -1) {
          _rooms[index] = _rooms[index].copyWith(
            members: serverMembers,
            memberCount: serverMembers.length,
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 서버에서 중간지점 요청
  Future<Map<String, dynamic>?> getMidpointFromServer(String roomId) async {
    try {
      return await _apiClient.getMidpoint(roomId);
    } catch (e) {
      return null;
    }
  }
}
