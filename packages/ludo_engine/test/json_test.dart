import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();

void main() {
  test('RulesConfig round trips and fills missing keys', () {
    const custom = RulesConfig(
      tripleDoubleSixCancelsTurn: true,
      mustUseBothDice: false,
      blockMoveUsesSum: true,
      canContinuePastOwnBlock: true,
      countSixesAcrossTurn: false,
      freeForAllPlaysOn: false,
      teamWinsWhenBothFinish: false,
      partnersFormJointBlocks: true,
      finishedPlayerRollsForPartner: false,
    );
    expect(RulesConfig.fromJson(_wire(custom.toJson())), custom);
    expect(RulesConfig.fromJson(const {}), const RulesConfig());
    expect(
      RulesConfig.fromJson(const {'blockMoveUsesSum': true}),
      const RulesConfig(blockMoveUsesSum: true),
    );
    expect(custom.hashCode, RulesConfig.fromJson(custom.toJson()).hashCode);
    expect(custom == const RulesConfig(), isFalse);
    expect(custom.toString(), contains('blockMoveUsesSum'));
    expect(
      () => RulesConfig.fromJson(const {'mustUseBothDice': 'yes'}),
      throwsFormatException,
    );
  });

  test('Move round trips in the documented shape', () {
    expect(Move.advance(red, 2, 5).toJson(), {
      'k': 'advance',
      'c': 'red',
      'p': [2],
      'd': 5,
    });
    for (final m in [
      Move.release(green, 1),
      Move.advance(red, 2, 5),
      Move.blockAdvance(blue, [3, 0], 4),
      Move.pass(yellow),
    ]) {
      final back = Move.fromJson(_wire(m.toJson()));
      expect(back, m);
      expect(back.hashCode, m.hashCode);
      expect(m.toString(), isNotEmpty);
    }
    expect(
      Move.blockAdvance(red, [2, 1], 3),
      Move.blockAdvance(red, [1, 2], 3),
    );
  });

  test('malformed moves throw FormatException', () {
    for (final bad in <Map<String, Object?>>[
      {},
      {
        'k': 'jump',
        'c': 'red',
        'p': [0],
        'd': 1,
      },
      {
        'k': 'advance',
        'c': 'pink',
        'p': [0],
        'd': 1,
      },
      {
        'k': 'advance',
        'c': 'red',
        'p': [0],
        'd': 7,
      },
      {
        'k': 'advance',
        'c': 'red',
        'p': [4],
        'd': 1,
      },
      {
        'k': 'advance',
        'c': 'red',
        'p': [0, 1],
        'd': 1,
      },
      {
        'k': 'release',
        'c': 'red',
        'p': [0],
        'd': 5,
      },
      {
        'k': 'blockAdvance',
        'c': 'red',
        'p': [0],
        'd': 2,
      },
      {
        'k': 'blockAdvance',
        'c': 'red',
        'p': [0, 0],
        'd': 2,
      },
      {
        'k': 'pass',
        'c': 'red',
        'p': [0],
        'd': 0,
      },
      {'k': 'advance', 'c': 'red', 'p': 'x', 'd': 1},
    ]) {
      expect(() => Move.fromJson(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('GameState, PieceRef, Block and MoveResult round trip', () {
    var s = GameState.newGame(
      mode: GameMode.teams,
      players: PlayerColor.values,
      rules: const RulesConfig(partnersFormJointBlocks: true),
    );
    s = applyRoll(s, 6, 3);
    expect(GameState.fromJson(_wire(s.toJson())), s);
    final r = applyMove(s, Move.release(red, 0));
    final back = MoveResult.fromJson(_wire(r.toJson()));
    expect(back, r);
    expect(back.hashCode, r.hashCode);

    const p = PieceRef(blue, 3);
    expect(PieceRef.fromJson(_wire(p.toJson())), p);
    expect(p.toString(), 'blue#3');
    expect(
      () => PieceRef.fromJson(const {'c': 'blue', 'i': 4}),
      throwsFormatException,
    );

    final b = Block(12, const [PieceRef(red, 0), PieceRef(yellow, 1)]);
    final bb = Block.fromJson(_wire(b.toJson()));
    expect(bb, b);
    expect(bb.hashCode, b.hashCode);
    expect(b.toString(), contains('12'));
  });

  test('GameState equality notices every field', () {
    final s = position(
      pieces: {
        red: [5, kAtHome, kAtHome, kAtHome],
      },
    );
    expect(s == GameState.fromJson(s.toJson()), isTrue);
    expect(s.hashCode, GameState.fromJson(s.toJson()).hashCode);
    expect(s == s.copyWith(turnNumber: 1), isFalse);
    expect(s == s.copyWith(pieces: {...s.pieces, red: allHome}), isFalse);
    expect(s == s.copyWith(forfeited: [blue]), isFalse);
    expect(s.toString(), startsWith('GameState('));
    expect(
      () => GameState.fromJson(const {'mode': 'teams'}),
      throwsFormatException,
    );
  });
}
