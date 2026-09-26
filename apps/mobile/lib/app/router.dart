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

/// Pages that never carry a `from` return address.
bool _isEntry(String path) =>
    path == '/' || path == '/login' || path == '/splash';

String _withFrom(String path, String? from) =>
    from == null ? path : '$path?from=${Uri.encodeComponent(from)}';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    // Nothing is behind a login: guests play free games (D33). Only a phone
    // login without a name is sent back to finish the name step.
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      final from =
          state.uri.queryParameters['from'] ??
          (_isEntry(path) ? null : state.uri.toString());
      if (!auth.hasValue && !auth.hasError) {
        return path == '/splash' ? null : _withFrom('/splash', from);
      }
      final session = auth.value;
      final verified = session != null && !session.isGuest;
      if (verified && !session.hasName) {
        return path == '/login' ? null : _withFrom('/login', from);
      }
      if (path == '/splash' || (path == '/login' && verified)) {
        return from ?? '/';
      }
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
