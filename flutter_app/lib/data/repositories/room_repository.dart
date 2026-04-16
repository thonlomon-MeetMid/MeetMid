import '../models/member.dart';
import '../models/room.dart';
import '../models/transport_mode.dart';

class RoomRepository {
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
}
