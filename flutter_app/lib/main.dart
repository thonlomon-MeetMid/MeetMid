import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/repositories/auth_repository.dart';
import 'data/services/api_client.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 앱 시작 전 로컬에 저장된 로그인 정보 로드
  final repo = AuthRepository(ApiClient());
  final savedUser = await repo.loadSavedUser();

  runApp(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref.read(authRepositoryProvider),
            initialUser: savedUser,
          ),
        ),
      ],
      child: const MeetMidApp(),
    ),
  );
}
