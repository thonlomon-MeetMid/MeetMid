import '../models/user.dart';

class AuthRepository {
  /// 더미 로그인 (실제 API 연동 시 교체)
  Future<User> login(String id, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return User(id: '1', name: '홍길동', email: '$id@meetmid.com');
  }

  /// 더미 회원가입
  Future<User> signup({
    required String userId,
    required String password,
    required String name,
    required String phone,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return User(id: '1', name: name, email: '$userId@meetmid.com');
  }

  /// 아이디 찾기
  Future<String?> findId(String name, String phone) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return 'user123';
  }

  /// 비밀번호 찾기
  Future<bool> findPassword(String userId, String phone) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }
}
