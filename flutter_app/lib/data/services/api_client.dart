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

  /// 방 목록 GET /rooms
  Future<List<Map<String, dynamic>>> getRooms() async {
    final response = await _dio.get('/rooms');
    return List<Map<String, dynamic>>.from(response.data['rooms'] as List);
  }

  /// 방 만들기 POST /room
  Future<Map<String, dynamic>> createRoom(String roomName, {String hostName = ''}) async {
    final response = await _dio.post(
      '/room',
      data: {'room_name': roomName, 'host_name': hostName},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 방 참여 POST /room/{roomId}/join
  Future<Map<String, dynamic>> joinRoom({
    required String roomId,
    required String name,
    required String address,
    required String transport,
  }) async {
    final response = await _dio.post(
      '/room/$roomId/join',
      data: {'name': name, 'address': address, 'transport': transport},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 멤버 강퇴 POST /room/{roomId}/kick
  Future<Map<String, dynamic>> kickMember({
    required String roomId,
    required String requesterName,
    required String targetName,
  }) async {
    final response = await _dio.post(
      '/room/$roomId/kick',
      data: {'requester_name': requesterName, 'target_name': targetName},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 방장 양도 POST /room/{roomId}/transfer-host
  Future<Map<String, dynamic>> transferHost({
    required String roomId,
    required String requesterName,
    required String newHostName,
  }) async {
    final response = await _dio.post(
      '/room/$roomId/transfer-host',
      data: {'requester_name': requesterName, 'new_host_name': newHostName},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 중간지점 요청 GET /midpoint/{roomId}
  Future<Map<String, dynamic>> getMidpoint(String roomId) async {
    final response = await _dio.get('/midpoint/$roomId');
    return response.data as Map<String, dynamic>;
  }
}
