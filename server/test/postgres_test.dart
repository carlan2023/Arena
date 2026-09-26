import 'package:arena_auth/arena_auth.dart' as auth;
import 'package:arena_server/arena_server.dart';
import 'package:arena_server/src/store/postgres_match_log.dart';
import 'package:arena_wallet/arena_wallet.dart' as wallet;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  late TestSchema db;
  final all = [...auth.migrations, ...wallet.migrations, ...serverMigrations];

  setUp(() async => db = await TestSchema.open());
  tearDown(() async => db.close());

  test(
    'migrations apply once, in order, even when started twice at once',
    () async {
      final results = await Future.wait([
        runMigrations(db.pool, all),
        runMigrations(db.pool, all),
      ]);
      final applied = [...results[0], ...results[1]];
      expect(applied, all.map((m) => m.id).toList());
      expect(await runMigrations(db.pool, all), isEmpty);
      final rows = await db.pool.execute(
        'SELECT id FROM schema_migrations ORDER BY applied_at, id',
      );
      expect(rows.map((r) => r[0]).toSet(), all.map((m) => m.id).toSet());
    },
    skip: skipWithoutDatabase,
  );

  test('duplicate migration ids are refused', () async {
    await expectLater(
      runMigrations(db.pool, [...serverMigrations, ...serverMigrations]),
      throwsArgumentError,
    );
  }, skip: skipWithoutDatabase);

  test('match log round trip', () async {
    await runMigrations(db.pool, all);
    final log = PostgresMatchLog(db.pool);
    const roomId = '11111111-1111-4111-8111-111111111111';
    const matchId = '22222222-2222-4222-8222-222222222222';
    final at = DateTime.utc(2026, 9, 26, 10);
    await log.roomCreated(
      RoomRecord(
        id: roomId,
        code: 'ABC234',
        mode: 'oneVsOne',
        seats: 2,
        stake: 0,
        rules: const {'mustUseBothDice': true},
        ownerUserId: 'u1',
        createdAt: at,
      ),
    );
    await log.matchStarted(
      MatchStartRecord(
        matchId: matchId,
        roomId: roomId,
        mode: 'oneVsOne',
        rules: const {},
        stake: 0,
        serverSeedHash: 'hash',
        clientSeed: 'a:b',
        startedAt: at,
        players: const [
          MatchPlayerRecord(seat: 0, userId: 'u1', color: 'red'),
          MatchPlayerRecord(seat: 1, userId: 'u2', color: 'yellow'),
        ],
      ),
    );
    await log.roomStatusChanged(roomId, 'playing');
    for (var i = 0; i < 3; i++) {
      await log.event(
        MatchEventRecord(
          matchId: matchId,
          index: i,
          kind: i.isEven ? EventKinds.roll : EventKinds.move,
          seat: 0,
          color: 'red',
          data: i.isEven
              ? {
                  'values': [6, i + 1],
                  'rollNumber': i ~/ 2,
                }
              : {'moves': <Object?>[], 'captured': <Object?>[]},
          auto: i == 2,
          at: at,
        ),
      );
    }
    var stored = (await log.loadMatch(matchId))!;
    expect(stored.status, MatchStatus.playing);
    expect(stored.serverSeed, isNull);
    expect(stored.roomCode, 'ABC234');
    expect(stored.rolls, [(6, 1), (6, 3)]);

    await log.matchEnded(
      MatchEndRecord(
        matchId: matchId,
        status: MatchStatus.finished,
        serverSeedHex: 'seed',
        endedAt: at,
        places: const {0: 1, 1: 2},
        forfeitedSeats: const {1},
        botSeats: const {},
      ),
    );
    stored = (await log.loadMatch(matchId))!;
    expect(stored.status, MatchStatus.finished);
    expect(stored.serverSeed, 'seed');
    final events = await log.events(matchId);
    expect(events.map((e) => e.kind), ['roll', 'move', 'roll']);
    expect(events.last.auto, isTrue);
    final players = await db.pool.execute(
      'SELECT seat, finish_place, forfeited FROM match_players ORDER BY seat',
    );
    expect(players.map((r) => [r[0], r[1], r[2]]).toList(), [
      [0, 1, false],
      [1, 2, true],
    ]);
    expect(await log.loadMatch('33333333-3333-4333-8333-333333333333'), isNull);
    // The same event index twice is a bug and must fail.
    await expectLater(
      log.event(
        MatchEventRecord(
          matchId: matchId,
          index: 0,
          kind: 'roll',
          seat: 0,
          color: 'red',
          data: const {},
          auto: false,
          at: at,
        ),
      ),
      throwsA(anything),
    );
  }, skip: skipWithoutDatabase);
}
