class Place {
  final String id;
  final String name;
  final String category;
  final String distance;
  final String address;
  final double rating;
  final int reviewCount;
  final bool aiRecommended;
  final double lat;
  final double lng;
  final String url;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.distance,
    required this.address,
    required this.rating,
    this.reviewCount = 0,
    this.aiRecommended = false,
    this.lat = 0.0,
    this.lng = 0.0,
    this.url = '',
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      distance: json['distance'] as String? ?? '',
      address: json['address'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      aiRecommended: json['aiRecommended'] as bool? ?? false,
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      url: json['url'] as String? ?? '',
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
        'lat': lat,
        'lng': lng,
        'url': url,
      };
}