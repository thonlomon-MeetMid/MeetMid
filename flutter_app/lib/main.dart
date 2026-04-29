import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/nickname_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 저장된 닉네임을 앱 시작 전에 로드해서 provider 초기값으로 주입
  final prefs = await SharedPreferences.getInstance();
  final savedNickname = prefs.getString('user_nickname') ?? '';

  runApp(
    ProviderScope(
      overrides: [
        nicknameProvider.overrideWith(
          (ref) => NicknameNotifier(initial: savedNickname),
        ),
      ],
      child: const MeetMidApp(),
    ),
  );
}
