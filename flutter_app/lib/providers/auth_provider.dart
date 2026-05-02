import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/api_client.dart';

class AuthState {
  final User? user;
  final bool isLoggedIn;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.user,
    this.isLoggedIn = false,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    User? user,
    bool? isLoggedIn,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo, {User? initialUser})
      : super(initialUser != null
            ? AuthState(user: initialUser, isLoggedIn: true)
            : const AuthState());

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _repo.login(username, password);
      state = AuthState(user: user, isLoggedIn: true);
      return true;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '아이디 또는 비밀번호가 올바르지 않습니다',
      );
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repo.register(
        name: name,
        username: username,
        email: email,
        password: password,
      );
      state = const AuthState();
      return true;
    } catch (e) {
      final msg = e.toString().contains('409') || e.toString().contains('사용 중')
          ? '이미 사용 중인 아이디 또는 이메일입니다'
          : '회원가입에 실패했습니다';
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState();
  }
}

final _apiClientProvider = Provider((ref) => ApiClient());

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.read(_apiClientProvider)));

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});
