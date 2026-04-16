import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';

class AuthState {
  final User? user;
  final bool isLoggedIn;
  final bool isLoading;

  const AuthState({this.user, this.isLoggedIn = false, this.isLoading = false});

  AuthState copyWith({User? user, bool? isLoggedIn, bool? isLoading}) {
    return AuthState(
      user: user ?? this.user,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState());

  Future<bool> login(String id, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await _repo.login(id, password);
      state = AuthState(user: user, isLoggedIn: true, isLoading: false);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<bool> signup({
    required String userId,
    required String password,
    required String name,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.signup(
        userId: userId,
        password: password,
        name: name,
        phone: phone,
      );
      state = const AuthState();
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  void logout() {
    state = const AuthState();
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});
