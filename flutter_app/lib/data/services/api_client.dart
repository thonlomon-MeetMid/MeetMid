import 'package:dio/dio.dart';

class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:5000';

  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
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
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'transport': transport,
    };
    if (userUuid.isNotEmpty) body['user_uuid'] = userUuid;
    final res = await _dio.post('/room/$roomId/join', data: body);
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

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final res = await _dio.get(
      '/places/search',
      queryParameters: {'query': query},
    );
    return List<Map<String, dynamic>>.from(res.data['places'] as List);
  }

  Future<Map<String, dynamic>> getMidpoint(String roomId) async {
    final res = await _dio.get('/midpoint/$roomId');
    return res.data as Map<String, dynamic>;
  }
}
