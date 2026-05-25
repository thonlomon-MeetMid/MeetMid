import '../models/member.dart';
import '../models/room.dart';
import '../models/transport_mode.dart';
import '../services/api_client.dart';

class RoomRepository {
  final ApiClient _apiClient = ApiClient();

  final List<Room> _rooms = [];

  Member _parseMember(Map<String, dynamic> m) => Member(
        id: (m['id'] as String?) ?? (m['name'] as String),
        name: m['name'] as String,
        departure: m['address'] as String,
        transport: TransportMode.values.firstWhere(
          (t) => t.name == (m['transport'] as String),
          orElse: () => TransportMode.transit,
        ),
        isDirectAdded: m['is_direct_added'] as bool? ?? false,
      );

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

  Future<List<Room>> fetchRoomsFromServer({String userId = ''}) async {
    final data = await _apiClient.getRooms(userId: userId);
    final fetched = data.map((d) {
      final serverMembers = (d['members'] as List<dynamic>)
          .map((m) => _parseMember(m as Map<String, dynamic>))
          .toList();
      return Room(
        id: d['room_id'] as String,
        name: d['room_name'] as String,
        hostId: (d['host_id'] as String?) ?? '',
        memberCount: serverMembers.length,
        members: serverMembers,
      );
    }).toList();
    _rooms
      ..clear()
      ..addAll(fetched);
    return List.unmodifiable(_rooms);
  }

  Future<Room?> createRoomOnServer(
    String roomName, {
    String hostName = '',
    String hostUuid = '',
    String password = '',
  }) async {
    try {
      final data = await _apiClient.createRoom(
        roomName,
        hostName: hostName,
        hostUuid: hostUuid,
        password: password,
      );
      final serverMembers = (data['members'] as List? ?? [])
          .map((m) => _parseMember(m as Map<String, dynamic>))
          .toList();
      final room = Room(
        id: data['room_id'] as String,
        name: data['room_name'] as String,
        hostId: (data['host_id'] as String?) ?? hostName,
        memberCount: serverMembers.length,
        members: serverMembers,
      );
      _rooms.add(room);
      return room;
    } catch (e) {
      // ignore: avoid_print
      print('[createRoomOnServer] 서버 오류: $e');
      return null;
    }
  }

  Future<bool> joinRoomOnServer({
    required String roomId,
    required String name,
    required String address,
    required String transport,
    String userUuid = '',
    bool isDirectAdded = false,
    String password = '',
  }) async {
    try {
      final data = await _apiClient.joinRoom(
        roomId: roomId,
        name: name,
        address: address,
        transport: transport,
        userUuid: userUuid,
        isDirectAdded: isDirectAdded,
        password: password,
      );
      if (data['ok'] == true) {
        final serverMembers = (data['members'] as List)
            .map((m) => _parseMember(m as Map<String, dynamic>))
            .toList();

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

  Future<bool> kickMemberOnServer({
    required String roomId,
    required String requesterName,
    required String targetName,
    String targetMemberId = '',
  }) async {
    try {
      final data = await _apiClient.kickMember(
        roomId: roomId,
        requesterName: requesterName,
        targetName: targetName,
        targetMemberId: targetMemberId,
      );
      if (data['ok'] == true) {
        final serverMembers = (data['members'] as List)
            .map((m) => _parseMember(m as Map<String, dynamic>))
            .toList();
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

  Future<bool> transferHostOnServer({
    required String roomId,
    required String requesterName,
    required String newHostName,
  }) async {
    try {
      final data = await _apiClient.transferHost(
        roomId: roomId,
        requesterName: requesterName,
        newHostName: newHostName,
      );
      if (data['ok'] == true) {
        final index = _rooms.indexWhere((r) => r.id == roomId);
        if (index != -1) {
          _rooms[index] = _rooms[index].copyWith(
            hostId: data['host_id'] as String,
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<({bool ok, bool roomDeleted})> leaveRoomOnServer({
    required String roomId,
    required String userName,
  }) async {
    try {
      final data = await _apiClient.leaveRoom(roomId: roomId, userName: userName);
      if (data['ok'] == true) {
        final roomDeleted = data['room_deleted'] as bool? ?? false;
        _rooms.removeWhere((r) => r.id == roomId);
        return (ok: true, roomDeleted: roomDeleted);
      }
      return (ok: false, roomDeleted: false);
    } catch (e) {
      return (ok: false, roomDeleted: false);
    }
  }

  Future<bool> updateMemberOnServer({
    required String roomId,
    required String requesterName,
    required String oldName,
    required String newName,
    required String address,
    required String transport,
  }) async {
    try {
      final data = await _apiClient.updateMember(
        roomId: roomId,
        requesterName: requesterName,
        oldName: oldName,
        newName: newName,
        address: address,
        transport: transport,
      );
      if (data['ok'] == true) {
        final serverMembers = (data['members'] as List)
            .map((m) => _parseMember(m as Map<String, dynamic>))
            .toList();
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

  Future<Map<String, dynamic>?> getMidpointFromServer(String roomId) async {
    try {
      return await _apiClient.getMidpoint(roomId);
    } catch (e) {
      return null;
    }
  }
}
