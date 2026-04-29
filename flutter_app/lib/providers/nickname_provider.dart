import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNicknameKey = 'user_nickname';

class NicknameNotifier extends StateNotifier<String> {
  NicknameNotifier({String initial = ''}) : super(initial);

  Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNicknameKey, name.trim());
    state = name.trim();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNicknameKey);
    state = '';
  }
}

final nicknameProvider = StateNotifierProvider<NicknameNotifier, String>(
  (ref) => NicknameNotifier(),
);
