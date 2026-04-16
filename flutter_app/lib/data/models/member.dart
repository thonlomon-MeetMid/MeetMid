import 'transport_mode.dart';

class Member {
  final String id;
  final String name;
  final String departure;
  final TransportMode transport;
  final int? travelMinutes;

  const Member({
    required this.id,
    required this.name,
    required this.departure,
    required this.transport,
    this.travelMinutes,
  });

  Member copyWith({
    String? id,
    String? name,
    String? departure,
    TransportMode? transport,
    int? travelMinutes,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      departure: departure ?? this.departure,
      transport: transport ?? this.transport,
      travelMinutes: travelMinutes ?? this.travelMinutes,
    );
  }

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      name: json['name'] as String,
      departure: json['departure'] as String,
      transport: TransportMode.values.firstWhere(
        (e) => e.name == json['transport'],
        orElse: () => TransportMode.transit,
      ),
      travelMinutes: json['travelMinutes'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'departure': departure,
        'transport': transport.name,
        'travelMinutes': travelMinutes,
      };
}
