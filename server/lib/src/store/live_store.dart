import 'dart:convert';

import 'package:arena_protocol/arena_protocol.dart' show Json;
import 'package:redis/redis.dart';

/// Where live rooms are written through so a restarted server can pick them
/// up again (protocol amendment 11). Rooms in memory stay the authority.
abstract interface class LiveRoomStore {
  /// Stores the latest snapshot of a room, replacing the previous one.
  Future<void> save(String code, Json snapshot);

  Future<void> delete(String code);

  /// Every stored snapshot.
  Future<List<Json>> loadAll();

  Future<void> close();
}

class InMemoryLiveRoomStore implements LiveRoomStore {
  final Map<String, String> _rooms = {};

  /// Codes currently stored.
  Iterable<String> get codes => _rooms.keys;

  Json? snapshot(String code) {
    final s = _rooms[code];
    return s == null ? null : jsonDecode(s) as Json;
  }

  @override
  Future<void> save(String code, Json snapshot) async {
    // Encoded so a test sees exactly what Redis would hold.
    _rooms[code] = jsonEncode(snapshot);
  }

  @override
  Future<void> delete(String code) async {
    _rooms.remove(code);
  }

  @override
  Future<List<Json>> loadAll() async => [
    for (final s in _rooms.values) jsonDecode(s) as Json,
  ];

  @override
  Future<void> close() async {}
}

/// Redis keys: `arena:room:<code>` holds the snapshot JSON with a TTL, and the
/// set `arena:rooms` lists the codes.
class RedisLiveRoomStore implements LiveRoomStore {
  RedisLiveRoomStore._(this._connection, this._command, this.ttl);

  static const _prefix = 'arena:room:';
  static const _index = 'arena:rooms';

  final RedisConnection _connection;
  final Command _command;
  final Duration ttl;

  /// Connects to `redis://[:password@]host[:port][/db]`.
  static Future<RedisLiveRoomStore> connect(
    String redisUrl, {
    Duration ttl = const Duration(hours: 6),
  }) async {
    final uri = Uri.parse(redisUrl);
    final connection = RedisConnection();
    final command = uri.scheme == 'rediss'
        ? await connection.connectSecure(
            uri.host,
            uri.hasPort ? uri.port : 6379,
          )
        : await connection.connect(uri.host, uri.hasPort ? uri.port : 6379);
    final userInfo = Uri.decodeComponent(uri.userInfo);
    if (userInfo.isNotEmpty) {
      final colon = userInfo.indexOf(':');
      final user = colon < 0 ? '' : userInfo.substring(0, colon);
      final pass = colon < 0 ? userInfo : userInfo.substring(colon + 1);
      await command.send_object(
        user.isEmpty ? ['AUTH', pass] : ['AUTH', user, pass],
      );
    }
    final db = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (db.isNotEmpty) await command.send_object(['SELECT', db]);
    return RedisLiveRoomStore._(connection, command, ttl);
  }

  @override
  Future<void> save(String code, Json snapshot) async {
    await _command.send_object([
      'SET',
      '$_prefix$code',
      jsonEncode(snapshot),
      'EX',
      '${ttl.inSeconds}',
    ]);
    await _command.send_object(['SADD', _index, code]);
  }

  @override
  Future<void> delete(String code) async {
    await _command.send_object(['DEL', '$_prefix$code']);
    await _command.send_object(['SREM', _index, code]);
  }

  @override
  Future<List<Json>> loadAll() async {
    final codes = await _command.send_object(['SMEMBERS', _index]) as List;
    final out = <Json>[];
    for (final code in codes) {
      final value = await _command.send_object(['GET', '$_prefix$code']);
      if (value is String) {
        out.add(jsonDecode(value) as Json);
      } else {
        // Expired by TTL.
        await _command.send_object(['SREM', _index, code]);
      }
    }
    return out;
  }

  @override
  Future<void> close() async {
    await _connection.close();
  }
}
