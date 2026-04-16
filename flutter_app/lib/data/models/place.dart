class Place {
  final String id;
  final String name;
  final String category;
  final String distance;
  final String address;
  final double rating;
  final bool aiRecommended;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.distance,
    required this.address,
    required this.rating,
    this.aiRecommended = false,
  });

  Place copyWith({
    String? id,
    String? name,
    String? category,
    String? distance,
    String? address,
    double? rating,
    bool? aiRecommended,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      distance: distance ?? this.distance,
      address: address ?? this.address,
      rating: rating ?? this.rating,
      aiRecommended: aiRecommended ?? this.aiRecommended,
    );
  }

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      distance: json['distance'] as String,
      address: json['address'] as String,
      rating: (json['rating'] as num).toDouble(),
      aiRecommended: json['aiRecommended'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'distance': distance,
        'address': address,
        'rating': rating,
        'aiRecommended': aiRecommended,
      };
}
