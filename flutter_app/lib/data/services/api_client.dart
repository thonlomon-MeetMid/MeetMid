import 'package:dio/dio.dart';

class ApiClient {
  static const String baseUrl = 'http://localhost:5000';

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

  /// Flask /recommend POST
  Future<String> recommendPlaces(String query) async {
    final response = await _dio.post(
      '/recommend',
      data: {'query': query},
    );
    return response.data['result'] as String;
  }

  /// 방 만들기 POST /room
  /// 성공 시 { room_id, room_name, members } 반환
  Future<Map<String, dynamic>> createRoom(String roomName) async {
    final response = await _dio.post(
      '/room',
      data: {'room_name': roomName},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 방 참여 POST /room/{roomId}/join
  /// 성공 시 { ok, members } 반환
  Future<Map<String, dynamic>> joinRoom({
    required String roomId,
    required String name,
    required String address,
    required String transport,
  }) async {
    final response = await _dio.post(
      '/room/$roomId/join',
      data: {
        'name': name,
        'address': address,
        'transport': transport,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// 중간지점 요청 GET /midpoint/{roomId}
  /// 성공 시 { midpoint: {lat, lng}, address, travel_times } 반환
  Future<Map<String, dynamic>> getMidpoint(String roomId) async {
    final response = await _dio.get('/midpoint/$roomId');
    return response.data as Map<String, dynamic>;
  }
}