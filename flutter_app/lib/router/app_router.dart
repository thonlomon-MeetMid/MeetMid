import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/find_id_screen.dart';
import '../screens/auth/find_pw_screen.dart';
import '../screens/main/main_shell.dart';
import '../screens/main/main_map_screen.dart';
import '../screens/main/room_list_screen.dart';
import '../screens/main/settings_screen.dart';
import '../screens/room/create_room_screen.dart';
import '../screens/room/find_room_screen.dart';
import '../screens/room/departure_input_screen.dart';
import '../screens/room/room_detail_screen.dart';
import '../screens/room/search_settings_screen.dart';
import '../screens/result/search_result_screen.dart';
import '../screens/result/place_recommend_screen.dart';
import '../screens/result/share_result_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// auth 상태 변화를 GoRouter에 알려주는 notifier
// ref.watch 대신 이 방식을 써야 라우터 인스턴스가 재생성되지 않음
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn = ref.read(authProvider).isLoggedIn;
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/map';
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/auth/find-id',
        builder: (context, state) => const FindIdScreen(),
      ),
      GoRoute(
        path: '/auth/find-pw',
        builder: (context, state) => const FindPwScreen(),
      ),

      // Main shell with bottom nav
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/map',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MainMapScreen(),
            ),
          ),
          GoRoute(
            path: '/rooms',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RoomListScreen(),
            ),
          ),
        ],
      ),

      // Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // Room routes
      GoRoute(
        path: '/room/create',
        builder: (context, state) => const CreateRoomScreen(),
      ),
      GoRoute(
        path: '/room/find',
        builder: (context, state) => const FindRoomScreen(),
      ),
      GoRoute(
        path: '/room/:roomId',
        builder: (context, state) => RoomDetailScreen(
          roomId: state.pathParameters['roomId']!,
        ),
        routes: [
          GoRoute(
            path: 'departure/:memberId',
            builder: (context, state) => DepartureInputScreen(
              roomId: state.pathParameters['roomId']!,
              memberId: state.pathParameters['memberId']!,
            ),
          ),
          GoRoute(
            path: 'search-settings',
            builder: (context, state) => SearchSettingsScreen(
              roomId: state.pathParameters['roomId']!,
            ),
          ),
          GoRoute(
            path: 'search-result',
            builder: (context, state) => SearchResultScreen(
              roomId: state.pathParameters['roomId']!,
            ),
          ),
          GoRoute(
            path: 'recommend',
            builder: (context, state) => PlaceRecommendScreen(
              roomId: state.pathParameters['roomId']!,
            ),
          ),
          GoRoute(
            path: 'share',
            builder: (context, state) => ShareResultScreen(
              roomId: state.pathParameters['roomId']!,
            ),
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    notifier.dispose();
    router.dispose();
  });

  return router;
});
