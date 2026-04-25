import '../models/member.dart';
import '../models/room.dart';
import '../models/transport_mode.dart';
import '../services/api_client.dart';

class RoomRepository {
  final ApiClient _apiClient = ApiClient();

  final List<Room> _rooms = [
    Room(
      id: '1',
      name: '대학 동기 모임',
      memberCount: 4,
      members: [
        const Member(id: '1', name: '김민준', departure: '강남역', transport: TransportMode.transit, travelMinutes: 22),
        const Member(id: '2', name: '이서연', departure: '홍대입구역', transport: TransportMode.transit, travelMinutes: 18),
        const Member(id: '3', name: '박지훈', departure: '잠실역', transport: TransportMode.car, travelMinutes: 35),
        const Member(id: '4', name: '최수아', departure: '신촌역', transport: TransportMode.walk, travelMinutes: 12),
      ],
    ),
    Room(
      id: '2',
      name: '팀 프로젝트 회의',
      memberCount: 3,
      members: [
        const Member(id: '1', name: '나', departure: '건대입구역', transport: TransportMode.transit, travelMinutes: 20),
        const Member(id: '2', name: '정태양', departure: '왕십리역', transport: TransportMode.transit, travelMinutes: 15),
        const Member(id: '3', name: '한나리', departure: '성수역', transport: TransportMode.walk, travelMinutes: 25),
      ],
    ),
    Room(
      id: '3',
      name: '친구들 저녁 약속',
      memberCount: 5,
      members: [
        const Member(id: '1', name: '나', departure: '합정역', transport: TransportMode.transit, travelMinutes: 28),
        const Member(id: '2', name: '윤다은', departure: '마포역', transport: TransportMode.walk, travelMinutes: 10),
        const Member(id: '3', name: '장현우', departure: '공덕역', transport: TransportMode.transit, travelMinutes: 20),
        const Member(id: '4', name: '임소희', departure: '여의도역', transport: TransportMode.transit, travelMinutes: 30),
        const Member(id: '5', name: '오준혁', departure: '영등포역', transport: TransportMode.car, travelMinutes: 25),
      ],
    ),
  ];

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

  // ✅ 서버에 방 만들기
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
      return null;
    }
  }

  // ✅ 서버에 방 참여 (출발지 포함)
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
      // 서버에서 받은 멤버 목록으로 로컬 업데이트
      if (data['ok'] == true) {
        final serverMembers = (data['members'] as List).map((m) {
          return Member(
            id: m['name'] as String, // 서버에 id 없으면 name 사용
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

  // ✅ 서버에서 중간지점 요청
  Future<Map<String, dynamic>?> getMidpointFromServer(String roomId) async {
    try {
      return await _apiClient.getMidpoint(roomId);
    } catch (e) {
      return null;
    }
  }
}