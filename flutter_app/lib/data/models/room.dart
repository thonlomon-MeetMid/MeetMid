import 'member.dart';

class Room {
  final String id;
  final String name;
  final String? description;
  final int memberCount;
  final List<Member> members;
  final String hostId;
  final String prompt; // 탐색 프롬프트

  const Room({
    required this.id,
    required this.name,
    this.description,
    required this.memberCount,
    required this.members,
    this.hostId = '',
    this.prompt = '',
  });

  Room copyWith({
    String? id,
    String? name,
    String? description,
    int? memberCount,
    List<Member>? members,
    String? hostId,
    String? prompt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      members: members ?? this.members,
      hostId: hostId ?? this.hostId,
      prompt: prompt ?? this.prompt,
    );
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      memberCount: json['memberCount'] as int,
      members: (json['members'] as List)
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList(),
      hostId: (json['hostId'] as String?) ?? '',
      prompt: (json['prompt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'memberCount': memberCount,
        'members': members.map((e) => e.toJson()).toList(),
        'hostId': hostId,
        'prompt': prompt,
      };
}