import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_client.dart';

const _kUserId = 'auth_user_id';
const _kUserName = 'auth_user_name';
const _kUserUsername = 'auth_user_username';
const _kUserEmail = 'auth_user_email';

class AuthRepository {
  final ApiClient _apiClient;
  AuthRepository(this._apiClient);

  Future<User?> loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kUserId);
    final name = prefs.getString(_kUserName);
    final username = prefs.getString(_kUserUsername);
    final email = prefs.getString(_kUserEmail);
    if (id == null || name == null) return null;
    return User(id: id, name: name, username: username ?? '', email: email ?? '');
  }

  Future<User> login(String username, String password) async {
    final data = await _apiClient.loginUser(username: username, password: password);
    final userMap = data['user'] as Map<String, dynamic>;
    final user = User(
      id: userMap['id'] as String,
      name: userMap['name'] as String,
      username: userMap['username'] as String? ?? username,
      email: userMap['email'] as String? ?? '',
    );
    await _saveUser(user);
    return user;
  }

  Future<User> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.register(
      name: name,
      username: username,
      email: email,
      password: password,
    );
    final userMap = data['user'] as Map<String, dynamic>;
    return User(
      id: userMap['id'] as String,
      name: userMap['name'] as String,
      username: userMap['username'] as String? ?? username,
      email: userMap['email'] as String? ?? email,
    );
  }

  Future<bool> checkUsername(String username) =>
      _apiClient.checkUsername(username);

  Future<bool> checkEmail(String email) =>
      _apiClient.checkEmail(email);

  Future<String> findUsername({required String name, required String email}) =>
      _apiClient.findUsername(name: name, email: email);

  Future<void> verifyForReset({required String username, required String email}) =>
      _apiClient.verifyForReset(username: username, email: email);

  Future<void> resetPassword({
    required String username,
    required String email,
    required String newPassword,
  }) =>
      _apiClient.resetPassword(username: username, email: email, newPassword: newPassword);

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserUsername);
    await prefs.remove(_kUserEmail);
  }

  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, user.id);
    await prefs.setString(_kUserName, user.name);
    await prefs.setString(_kUserUsername, user.username);
    await prefs.setString(_kUserEmail, user.email);
  }
}
