import 'package:dio/dio.dart';
import '../models/place.dart';

class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:5000';

  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  Dio get dio => _dio;

  // ── 인증 ────────────────────────────────────────────────────

  Future<bool> checkUsername(String username) async {
    final res = await _dio.get('/auth/check-username/$username');
    return res.data['available'] as bool;
  }

  Future<bool> checkEmail(String email) async {
    final res = await _dio.get(
      '/auth/check-email',
      queryParameters: {'email': email},
    );
    return res.data['available'] as bool;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'name': name,
      'username': username,
      'email': email,
      'password': password,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginUser({
    required String username,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<String> findUsername({
    required String name,
    required String email,
  }) async {
    final res = await _dio.post('/auth/find-username', data: {
      'name': name,
      'email': email,
    });
    return res.data['username'] as String;
  }

  Future<void> verifyForReset({
    required String username,
    required String email,
  }) async {
    await _dio.post('/auth/find-pw/verify', data: {
      'username': username,
      'email': email,
    });
  }

  Future<void> resetPassword({
    required String username,
    required String email,
    required String newPassword,
  }) async {
    await _dio.post('/auth/reset-password', data: {
      'username': username,
      'email': email,
      'new_password': newPassword,
    });
  }

  // ── 방 ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRooms({String userId = ''}) async {
    final res = await _dio.get(
      '/rooms',
      queryParameters: userId.isNotEmpty ? {'user_id': userId} : null,
    );
    return List<Map<String, dynamic>>.from(res.data['rooms'] as List);
  }

  Future<Map<String, dynamic>> createRoom(
    String roomName, {
    String hostName = '',
    String hostUuid = '',
  }) async {
    final body = <String, dynamic>{'room_name': roomName};
    if (hostUuid.isNotEmpty) {
      body['host_uuid'] = hostUuid;
    } else {
      body['host_name'] = hostName;
    }
    final res = await _dio.post('/room', data: body);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinRoom({
    required String roomId,
    required String name,
    String address = '',
    String transport = 'transit',
    String userUuid = '',
    bool isDirectAdded = false,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'transport': transport,
    };
    if (userUuid.isNotEmpty) body['user_uuid'] = userUuid;
    if (isDirectAdded) body['is_direct_added'] = true;
    final res = await _dio.post('/room/$roomId/join', data: body);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMember({
    required String roomId,
    required String requesterName,
    required String oldName,
    required String newName,
    required String address,
    required String transport,
  }) async {
    final res = await _dio.put('/room/$roomId/member', data: {
      'requester_name': requesterName,
      'old_name': oldName,
      'new_name': newName,
      'address': address,
      'transport': transport,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getRoomsAll({
    String userId = '',
    String search = '',
  }) async {
    final params = <String, String>{};
    if (userId.isNotEmpty) params['user_id'] = userId;
    if (search.isNotEmpty) params['search'] = search;
    final res = await _dio.get(
      '/rooms/all',
      queryParameters: params.isNotEmpty ? params : null,
    );
    return List<Map<String, dynamic>>.from(res.data['rooms'] as List);
  }

  Future<Map<String, dynamic>> kickMember({
    required String roomId,
    required String requesterName,
    required String targetName,
  }) async {
    final res = await _dio.post('/room/$roomId/kick', data: {
      'requester_name': requesterName,
      'target_name': targetName,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> transferHost({
    required String roomId,
    required String requesterName,
    required String newHostName,
  }) async {
    final res = await _dio.post('/room/$roomId/transfer-host', data: {
      'requester_name': requesterName,
      'new_host_name': newHostName,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> leaveRoom({
    required String roomId,
    required String userName,
  }) async {
    final res = await _dio.post('/room/$roomId/leave', data: {
      'user_name': userName,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> geocode(String address) async {
    try {
      final res = await _dio.get('/geocode', queryParameters: {'address': address});
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get(
        '/reverse-geocode',
        queryParameters: {'lat': '$lat', 'lng': '$lng'},
      );
      return (res.data['address'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final res = await _dio.get(
      '/places/search',
      queryParameters: {'query': query},
    );
    return List<Map<String, dynamic>>.from(res.data['places'] as List);
  }

  Future<Map<String, dynamic>> getMidpoint(String roomId, {String criteria = 'distanceFair', bool polyline = false, String prompt = ''}) async {
    final params = <String, dynamic>{
      'criteria': criteria,
      'polyline': polyline ? '1' : '0',
    };
    if (prompt.isNotEmpty) params['prompt'] = prompt;
    final res = await _dio.get('/midpoint/$roomId', queryParameters: params);
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getPolylines(String roomId, {required double lat, required double lng}) async {
    try {
      final res = await _dio.get(
        '/midpoint/$roomId/polylines',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      return res.data['polylines'] as List? ?? [];
    } catch (_) {
      return [];
    }
  }

  // 방의 프롬프트를 Supabase에 저장
  Future<bool> updateRoomPrompt({
    required String roomId,
    required String prompt,
  }) async {
    try {
      await _dio.patch('/room/$roomId/prompt', data: {'prompt': prompt});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateLocation({
    required String roomId,
    required String memberName,
    required double lat,
    required double lng,
    required bool shared,
  }) async {
    try {
      await _dio.post('/room/$roomId/location', data: {
        'member_name': memberName,
        'lat': lat,
        'lng': lng,
        'shared': shared,
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getLiveLocations(String roomId) async {
    try {
      final res = await _dio.get('/room/$roomId/locations');
      return List<Map<String, dynamic>>.from(res.data['locations'] as List);
    } catch (_) {
      return [];
    }
  }

  Future<List<Place>> getPlaceRecommendations({
    required String roomId,
    required String prompt,
    required double lat,
    required double lng,
    String category = '',
    int radius = 1000,
    int minRadius = 0,
    int size = 5,
  }) async {
    try {
      final params = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'size': size,
      };
      if (minRadius > 0) params['min_radius'] = minRadius;
      if (prompt.isNotEmpty) params['prompt'] = prompt;
      if (category.isNotEmpty) params['category'] = category;
      final res = await _dio.get('/room/$roomId/places', queryParameters: params);
      final docs = res.data['places'] as List? ?? [];
      return docs.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> startSearch(String roomId, String criteria) async {
    try {
      await _dio.post('/room/$roomId/start-search',
          queryParameters: {'criteria': criteria});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getSearchStatus(String roomId) async {
    try {
      final res = await _dio.get('/room/$roomId/search-status');
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return {'started': false, 'criteria': 'distanceFair'};
    }
  }
}