import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../game/local_game.dart';
import '../online/auth.dart';
import '../online/config.dart';
import '../ui/home_screen.dart';
import '../ui/local_game_screen.dart';
import '../ui/local_setup_screen.dart';
import '../ui/login_screen.dart';
import '../ui/room_screen.dart';

/// Where a signed out player may still go: pass and play works offline.
bool _isOpen(String path) =>
    path == '/login' || path == '/splash' || path.startsWith('/local');

String _withFrom(String path, String? from) =>
    from == null ? path : '$path?from=${Uri.encodeComponent(from)}';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      final from =
          state.uri.queryParameters['from'] ??
          (_isOpen(path) || path == '/' ? null : state.uri.toString());
      if (!auth.hasValue && !auth.hasError) {
        return path == '/splash' ? null : _withFrom('/splash', from);
      }
      final loggedIn = auth.value?.hasName ?? false;
      if (!loggedIn) {
        if (path == '/splash' || !_isOpen(path)) {
          return _withFrom('/login', from);
        }
        return null;
      }
      if (path == '/splash' || path == '/login') return from ?? '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/local',
        builder: (context, _) => LocalSetupScreen(
          onStart: (config) => context.push('/local/play', extra: config),
        ),
      ),
      GoRoute(
        path: '/local/play',
        redirect: (_, state) =>
            state.extra is LocalGameConfig ? null : '/local',
        builder: (_, state) =>
            LocalGameScreen(config: state.extra! as LocalGameConfig),
      ),
      GoRoute(
        path: '/room/:code',
        redirect: (_, state) {
          final raw = state.pathParameters['code']!;
          final code = raw.toUpperCase();
          if (!isRoomCode(code)) return '/';
          return code == raw ? null : '/room/$code';
        },
        builder: (_, state) => RoomScreen(code: state.pathParameters['code']!),
      ),
      // Invite links: https://<server>/r/CODE (protocol amendment 13).
      GoRoute(
        path: '/r/:code',
        redirect: (_, state) =>
            '/room/${state.pathParameters['code']!.toUpperCase()}',
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
