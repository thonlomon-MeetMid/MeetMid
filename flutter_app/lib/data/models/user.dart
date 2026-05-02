class User {
  final String id;
  final String name;
  final String username;
  final String email;

  const User({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
  });

  User copyWith({String? id, String? name, String? username, String? email}) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'email': email,
      };
}
