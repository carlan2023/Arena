import 'package:arena_auth/arena_auth.dart' as auth;
import 'package:arena_server/arena_server.dart';
import 'package:arena_server/src/store/postgres_match_log.dart';
import 'package:arena_wallet/arena_wallet.dart' as wallet;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('InMemoryMatchLog', () {
    recentMatchesTests(() async => (InMemoryMatchLog(), () async {}));
  });

  group('PostgresMatchLog', skip: skipWithoutDatabase, () {
    recentMatchesTests(() async {
      final db = await TestSchema.open();
      await runMigrations(db.pool, [
        ...auth.migrations,
        ...wallet.migrations,
        ...serverMigrations,
      ]);
      return (PostgresMatchLog(db.pool), db.close);
    });
  });
}

void recentMatchesTests(
  Future<(MatchLog, Future<void> Function())> Function() open,
) {
  late MatchLog log;
  setUp(() async {
    final (l, close) = await open();
    log = l;
    addTearDown(close);
  });

  final start = DateTime.utc(2026, 10, 13, 9);
  var n = 0;

  /// Starts a match for [players] (user id, name, avatar, bot) and returns
  /// its id.
  Future<String> started(
    List<(String, String, int, bool)> players, {
    String mode = 'oneVsOne',
  }) async {
    n++;
    final roomId = '11111111-1111-4111-8111-${'$n'.padLeft(12, '0')}';
    final matchId = '22222222-2222-4222-8222-${'$n'.padLeft(12, '0')}';
    await log.roomCreated(
      RoomRecord(
        id: roomId,
        code: 'ROOM$n',
        mode: mode,
        seats: players.length,
        stake: 0,
        rules: const {},
        ownerUserId: players.first.$1,
        createdAt: start,
      ),
    );
    await log.matchStarted(
      MatchStartRecord(
        matchId: matchId,
        roomId: roomId,
        mode: mode,
        rules: const {},
        stake: 0,
        serverSeedHash: 'hash',
        clientSeed: 'seed',
        startedAt: start,
        players: [
          for (var i = 0; i < players.length; i++)
            MatchPlayerRecord(
              seat: i,
              userId: players[i].$1,
              color: 'c$i',
              displayName: players[i].$2,
              avatar: players[i].$3,
              isBot: players[i].$4,
            ),
        ],
      ),
    );
    return matchId;
  }

  Future<void> ended(
    String matchId,
    int minutes, {
    Map<int, int> places = const {},
    Set<int> bots = const {},
    MatchStatus status = MatchStatus.finished,
  }) => log.matchEnded(
    MatchEndRecord(
      matchId: matchId,
      status: status,
      serverSeedHex: 'seed',
      endedAt: start.add(Duration(minutes: minutes)),
      places: places,
      forfeitedSeats: const {},
      botSeats: bots,
    ),
  );

  test('lists ended matches newest first, with each player', () async {
    final first = await started([
      ('a', 'Allan', 3, false),
      ('b', 'Bo', 4, false),
    ]);
    await ended(first, 10, places: {0: 2, 1: 1}, bots: {1});
    final withBot = await started([
      ('a', 'Allan', 5, false),
      ('bot:1', 'Bot 2', 1, true),
    ]);
    await ended(withBot, 20, places: {0: 1, 1: 2}, bots: {1});
    final dropped = await started([
      ('a', 'Allan', 5, false),
      ('c', 'Cy', 0, false),
    ]);
    await ended(dropped, 30, status: MatchStatus.abandoned);
    await started([('a', 'Allan', 5, false), ('d', 'Di', 0, false)]);
    final others = await started([('x', 'X', 0, false), ('y', 'Y', 0, false)]);
    await ended(others, 40);

    final recent = await log.recentMatches('a');
    expect(recent.map((m) => m.matchId), [dropped, withBot, first]);
    expect(recent.first.status, MatchStatus.abandoned);
    expect(recent.first.players.map((p) => p.place), [null, null]);
    expect(recent.first.endedAt, start.add(const Duration(minutes: 30)));

    final bot = recent[1].players;
    expect(
      bot.map((p) => (p.seat, p.displayName, p.avatar, p.isBot, p.place)),
      [(0, 'Allan', 5, false, 1), (1, 'Bot 2', 1, true, 2)],
    );
    expect(recent[2].players.map((p) => p.avatar), [3, 4]);
    expect(recent[2].players.last.isBot, isTrue, reason: 'took over later');
    expect(recent[2].mode, 'oneVsOne');

    expect(await log.recentMatches('nobody'), isEmpty);
    expect((await log.recentMatches('a', limit: 2)).map((m) => m.matchId), [
      dropped,
      withBot,
    ]);
  });
}
