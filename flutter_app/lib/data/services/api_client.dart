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
}
