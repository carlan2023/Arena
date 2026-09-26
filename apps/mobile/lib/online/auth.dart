import 'dart:convert';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Proves a phone number and returns the ID token the server checks.
/// Firebase phone auth will implement this later (M0.5, D16).
abstract interface class PhoneAuth {
  Future<void> sendCode(String phone);

  /// Throws [AuthException] for a wrong code.
  Future<String> verifyCode(String phone, String code);
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// D16: with AUTH_PROVIDER=fake the code is always 123456 and the token is
/// `fake:+256...`.
class FakePhoneAuth implements PhoneAuth {
  const FakePhoneAuth();

  static const code = '123456';

  @override
  Future<void> sendCode(String phone) async {}

  @override
  Future<String> verifyCode(String phone, String code) async {
    if (code != FakePhoneAuth.code) {
      throw const AuthException('That code is not right');
    }
    return 'fake:$phone';
  }
}

/// A logged in player.
class Session {
  const Session({required this.token, required this.user});

  final String token;
  final UserView user;

  /// Players pick a name before they reach the home screen.
  bool get hasName => user.displayName.trim().isNotEmpty;

  /// Guests play free games only; paid play needs a phone login (D33).
  bool get isGuest => user.isGuest;

  Map<String, Object?> toJson() => {'token': token, 'user': user.toJson()};

  factory Session.fromJson(Map<String, Object?> j) => Session(
    token: j['token']! as String,
    user: UserView.fromJson((j['user']! as Map).cast<String, Object?>()),
  );
}

/// Keeps the session across app restarts, so a killed app can rejoin.
abstract interface class SessionStore {
  Future<Session?> load();
  Future<void> save(Session? session);
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);
  Session? session;

  @override
  Future<Session?> load() async => session;

  @override
  Future<void> save(Session? session) async => this.session = session;
}

class PrefsSessionStore implements SessionStore {
  static const _key = 'arena.session';

  @override
  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return Session.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      await prefs.remove(_key);
      return null;
    }
  }

  @override
  Future<void> save(Session? session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(session.toJson()));
    }
  }
}

final phoneAuthProvider = Provider<PhoneAuth>((ref) => const FakePhoneAuth());
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => PrefsSessionStore(),
);

final authProvider = AsyncNotifierProvider<AuthController, Session?>(
  AuthController.new,
);

/// The current session: null until the player first goes online.
class AuthController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(sessionStoreProvider).load();

  Future<Session>? _starting;

  /// The current session, or a new guest one. Free play never asks for a
  /// phone number (D33).
  Future<Session> ensureSession() async {
    final current = state.value;
    if (current != null) return current;
    return _starting ??= _startGuest().whenComplete(() => _starting = null);
  }

  /// Replaces a guest session the server no longer accepts, for example
  /// after a server restart with a new secret.
  Future<Session> renewGuest() async {
    await ref.read(sessionStoreProvider).save(null);
    state = const AsyncData(null);
    return ensureSession();
  }

  Future<Session> _startGuest() async {
    final session = await ref.read(arenaApiProvider).guest();
    await ref.read(sessionStoreProvider).save(session);
    state = AsyncData(session);
    return session;
  }

  /// Checks the code, logs in to the server and keeps the session.
  Future<Session> login(String phone, String code) async {
    final idToken = await ref.read(phoneAuthProvider).verifyCode(phone, code);
    final session = await ref.read(arenaApiProvider).login(idToken);
    await ref.read(sessionStoreProvider).save(session);
    state = AsyncData(session);
    return session;
  }

  Future<void> setDisplayName(String name) async {
    final session = state.value;
    if (session == null) return;
    final user = await ref
        .read(arenaApiProvider)
        .setDisplayName(session.token, name);
    final next = Session(token: session.token, user: user);
    await ref.read(sessionStoreProvider).save(next);
    state = AsyncData(next);
  }

  Future<void> logout() async {
    await ref.read(sessionStoreProvider).save(null);
    state = const AsyncData(null);
  }
}
