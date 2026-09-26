import 'package:arena_protocol/client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ludo_engine/ludo_engine.dart';

import 'auth.dart';
import 'config.dart';

/// The HTTP routes the app uses (protocol.md). Faked in tests.
abstract interface class ArenaApi {
  Future<Session> login(String idToken);
  Future<UserView> setDisplayName(String token, String name);
  Future<RoomView> createRoom(
    String token, {
    required GameMode mode,
    required int seats,
  });
  Future<RoomView> getRoom(String token, String code);
}

/// Talks to the server through the shared [ArenaClient].
class HttpArenaApi implements ArenaApi {
  HttpArenaApi(this.baseUrl, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  ArenaClient _client(String? token) =>
      ArenaClient(baseUrl: baseUrl, httpClient: _http)..sessionToken = token;

  @override
  Future<Session> login(String idToken) async {
    final c = _client(null);
    final user = await c.login(idToken);
    return Session(token: c.sessionToken!, user: user);
  }

  @override
  Future<UserView> setDisplayName(String token, String name) =>
      _client(token).setDisplayName(name);

  @override
  Future<RoomView> createRoom(
    String token, {
    required GameMode mode,
    required int seats,
  }) => _client(token).createRoom(mode: mode, seats: seats);

  @override
  Future<RoomView> getRoom(String token, String code) =>
      _client(token).getRoom(code);
}

final arenaApiProvider = Provider<ArenaApi>(
  (ref) => HttpArenaApi(Uri.parse(kServerUrl)),
);
