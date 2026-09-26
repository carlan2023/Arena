import 'package:postgres/postgres.dart';

import 'match_log.dart';

class PostgresMatchLog implements MatchLog {
  PostgresMatchLog(this._pool);
  final Pool _pool;

  @override
  Future<void> roomCreated(RoomRecord room) async {
    await _pool.execute(
      Sql.named('''
INSERT INTO rooms (id, code, mode, seats, stake, rules, owner_user_id, status, created_at, updated_at)
VALUES (@id:uuid, @code, @mode, @seats:int4, @stake:int8, @rules:jsonb, @owner, 'waiting', @at:timestamptz, @at:timestamptz)
ON CONFLICT (id) DO NOTHING'''),
      parameters: {
        'id': room.id,
        'code': room.code,
        'mode': room.mode,
        'seats': room.seats,
        'stake': room.stake,
        'rules': room.rules,
        'owner': room.ownerUserId,
        'at': room.createdAt.toUtc(),
      },
    );
  }

  @override
  Future<void> roomStatusChanged(String roomId, String status) async {
    await _pool.execute(
      Sql.named(
        'UPDATE rooms SET status = @s, updated_at = now() WHERE id = @id:uuid',
      ),
      parameters: {'id': roomId, 's': status},
    );
  }

  @override
  Future<void> matchStarted(MatchStartRecord m) async {
    await _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('''
INSERT INTO matches (id, room_id, mode, rules, stake, server_seed_hash, client_seed, status, started_at)
VALUES (@id:uuid, @room:uuid, @mode, @rules:jsonb, @stake:int8, @hash, @client, 'playing', @at:timestamptz)
ON CONFLICT (id) DO NOTHING'''),
        parameters: {
          'id': m.matchId,
          'room': m.roomId,
          'mode': m.mode,
          'rules': m.rules,
          'stake': m.stake,
          'hash': m.serverSeedHash,
          'client': m.clientSeed,
          'at': m.startedAt.toUtc(),
        },
      );
      for (final p in m.players) {
        await tx.execute(
          Sql.named('''
INSERT INTO match_players (match_id, seat, user_id, color)
VALUES (@id:uuid, @seat:int4, @user, @color)
ON CONFLICT DO NOTHING'''),
          parameters: {
            'id': m.matchId,
            'seat': p.seat,
            'user': p.userId,
            'color': p.color,
          },
        );
      }
    });
  }

  @override
  Future<void> event(MatchEventRecord e) async {
    await _pool.execute(
      Sql.named(
        '''
INSERT INTO moves (match_id, idx, kind, seat, color, data, auto, at)
VALUES (@id:uuid, @idx:int4, @kind, @seat:int4, @color, @data:jsonb, @auto:boolean, @at:timestamptz)''',
      ),
      parameters: {
        'id': e.matchId,
        'idx': e.index,
        'kind': e.kind,
        'seat': e.seat,
        'color': e.color,
        'data': e.data,
        'auto': e.auto,
        'at': e.at.toUtc(),
      },
    );
  }

  @override
  Future<void> matchEnded(MatchEndRecord end) async {
    await _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('''
UPDATE matches SET status = @status, server_seed = @seed, ended_at = @at:timestamptz
WHERE id = @id:uuid'''),
        parameters: {
          'id': end.matchId,
          'status': end.status.name,
          'seed': end.serverSeedHex,
          'at': end.endedAt.toUtc(),
        },
      );
      final rows = await tx.execute(
        Sql.named('SELECT seat FROM match_players WHERE match_id = @id:uuid'),
        parameters: {'id': end.matchId},
      );
      for (final row in rows) {
        final seat = row[0] as int;
        await tx.execute(
          Sql.named('''
UPDATE match_players SET finish_place = @place:int4, forfeited = @f:boolean, is_bot = @b:boolean
WHERE match_id = @id:uuid AND seat = @seat:int4'''),
          parameters: {
            'id': end.matchId,
            'seat': seat,
            'place': end.places[seat],
            'f': end.forfeitedSeats.contains(seat),
            'b': end.botSeats.contains(seat),
          },
        );
      }
    });
  }

  @override
  Future<StoredMatch?> loadMatch(String matchId) async {
    final rows = await _pool.execute(
      Sql.named('''
SELECT m.status, m.server_seed, m.server_seed_hash, m.client_seed, r.code
FROM matches m JOIN rooms r ON r.id = m.room_id
WHERE m.id = @id:uuid'''),
      parameters: {'id': matchId},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return StoredMatch(
      id: matchId,
      status: MatchStatus.values.byName(r[0] as String),
      serverSeed: r[1] as String?,
      serverSeedHash: r[2] as String,
      clientSeed: r[3] as String,
      roomCode: r[4] as String,
      rolls: rollsOf(await events(matchId)),
    );
  }

  @override
  Future<List<MatchEventRecord>> events(String matchId) async {
    final rows = await _pool.execute(
      Sql.named('''
SELECT idx, kind, seat, color, data, auto, at FROM moves
WHERE match_id = @id:uuid ORDER BY idx'''),
      parameters: {'id': matchId},
    );
    return [
      for (final r in rows)
        MatchEventRecord(
          matchId: matchId,
          index: r[0] as int,
          kind: r[1] as String,
          seat: r[2] as int,
          color: r[3] as String,
          data: (r[4] as Map).cast<String, Object?>(),
          auto: r[5] as bool,
          at: r[6] as DateTime,
        ),
    ];
  }
}
