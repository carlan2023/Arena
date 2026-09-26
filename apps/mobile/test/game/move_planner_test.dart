import 'package:arena/game/move_planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;
const yellow = PlayerColor.yellow;

GameState rolled(GameState s, int a, int b) => applyRoll(s, a, b);

GameState position(
  Map<PlayerColor, List<int>> pieces, {
  List<PlayerColor> players = const [red, green],
  GameMode mode = GameMode.freeForAll,
}) => GameState.custom(
  mode: mode,
  players: players,
  pieces: pieces,
  current: players.first,
);

void main() {
  test('worked example 1: release with the 6; a release is never combined', () {
    final s = rolled(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      6,
      3,
    );
    final planner = MovePlanner(s);
    expect(planner.movablePieces, hasLength(4));
    final options = planner.optionsFor(const PieceRef(red, 0));
    final single = options.where((o) => o.kind == OptionKind.single);
    final both = options.where((o) => o.kind == OptionKind.both);
    expect(single.single.target, 0);
    expect(single.single.moves.single.kind, MoveKind.release);
    expect(both, isEmpty, reason: 'D34: release plus a move stays two steps');
  });

  test('play, undo and the step list', () {
    final s = rolled(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      6,
      3,
    );
    final planner = MovePlanner(s);
    expect(planner.canUndo, isFalse);
    planner.play([Move.release(red, 2)]);
    expect(planner.canUndo, isTrue);
    expect(planner.current.pieces[red]![2], 0);
    expect(planner.undo(), isTrue);
    expect(planner.current, s);
    expect(planner.steps, isEmpty);

    planner.play([Move.release(red, 2), Move.advance(red, 2, 3)]);
    expect(planner.rollEnded, isTrue);
    expect(planner.canUndo, isFalse, reason: 'no undo after the last die');
    expect(planner.steps, [Move.release(red, 2), Move.advance(red, 2, 3)]);
    expect(planner.legalSteps, isEmpty);
    expect(() => planner.play([Move.advance(red, 2, 1)]), throwsA(anything));
  });

  test('an illegal step throws and leaves the plan unchanged', () {
    final s = rolled(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      6,
      3,
    );
    final planner = MovePlanner(s);
    expect(
      () => planner.play([Move.advance(red, 0, 3)]),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(planner.steps, isEmpty);
    expect(
      () => planner.play([Move.release(red, 0), Move.advance(red, 1, 3)]),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(planner.steps, isEmpty, reason: 'play is all or nothing');
  });

  group('D34: a single opponent 4 squares ahead, roll 4 and 4', () {
    // Red piece 0 on square 10, a single yellow piece on square 14.
    const yellowOn14 = 40;
    GameState reported({required bool otherPieceCanMove}) => rolled(
      position(
        {
          red: [10, otherPieceCanMove ? 30 : kAtHome, kAtHome, kAtHome],
          yellow: [yellowOn14, kAtHome, kAtHome, kAtHome],
        },
        players: const [red, yellow],
        mode: GameMode.oneVsOne,
      ),
      4,
      4,
    );

    test('the both spot is one combined step that passes without capture', () {
      final planner = MovePlanner(reported(otherPieceCanMove: true));
      final both = planner
          .optionsFor(const PieceRef(red, 0))
          .where((o) => o.kind == OptionKind.both)
          .single;
      expect(both.target, 18);
      expect(both.moves, [Move.combined(red, 0, 4, 4)]);
      expect(both.dice, [4, 4]);
      planner.play(both.moves);
      expect(planner.results.single.captured, isEmpty);
      expect(planner.current.pieces[yellow]![0], yellowOn14);
    });

    test('the single 4 captures, then only another piece takes the 4', () {
      final planner = MovePlanner(reported(otherPieceCanMove: true));
      final capture = planner
          .optionsFor(const PieceRef(red, 0))
          .where((o) => o.kind == OptionKind.single && o.target == 14)
          .single;
      planner.play(capture.moves);
      expect(planner.results.single.captured, [const PieceRef(yellow, 0)]);
      expect(planner.movablePieces, {const PieceRef(red, 1)});
      expect(planner.optionsFor(const PieceRef(red, 0)), isEmpty);
      expect(planner.canUndo, isTrue);
      planner.undo();
      expect(planner.current.pieces[yellow]![0], yellowOn14);
    });

    test('with no other piece to move, the capture spot is not offered', () {
      final planner = MovePlanner(reported(otherPieceCanMove: false));
      final options = planner.optionsFor(const PieceRef(red, 0));
      expect(options.where((o) => o.target == 14), isEmpty);
      expect(options.single.kind, OptionKind.both);
      expect(planner.forcedRest, [Move.combined(red, 0, 4, 4)]);
    });
  });

  test('forced rest when only one sequence remains', () {
    final s = rolled(
      position({
        red: [40, kFinished, kFinished, kFinished],
      }),
      2,
      3,
    );
    final planner = MovePlanner(s);
    expect(planner.forcedRest, isNotNull);
    planner.play(planner.forcedRest!);
    expect(planner.rollEnded, isTrue);
    expect(planner.results.last.state.pieces[red]![0], 45);
  });

  test('not forced when there is a real choice', () {
    final s = rolled(
      position({
        red: [10, 20, kAtHome, kAtHome],
      }),
      2,
      3,
    );
    expect(MovePlanner(s).forcedRest, isNull);
  });

  test('block option on a double', () {
    final s = rolled(
      position({
        red: [5, 5, kAtHome, kAtHome],
      }),
      4,
      4,
    );
    final options = MovePlanner(s).optionsFor(const PieceRef(red, 0));
    final block = options.where((o) => o.kind == OptionKind.block).single;
    expect(block.moves.single.kind, MoveKind.blockAdvance);
    expect(block.target, 9);
    expect(block.dice, [4, 4]);
  });

  test('pass option only with R2 off', () {
    final base = position({
      red: [10, 20, kAtHome, kAtHome],
    });
    final strict = MovePlanner(rolled(base, 2, 3));
    strict.play([Move.advance(red, 0, 2)]);
    expect(strict.passOption, isNull);

    final loose = MovePlanner(
      rolled(
        GameState.custom(
          mode: GameMode.freeForAll,
          players: const [red, green],
          rules: const RulesConfig(mustUseBothDice: false),
          pieces: {
            red: [10, 20, kAtHome, kAtHome],
          },
        ),
        2,
        3,
      ),
    );
    loose.play([Move.advance(red, 0, 2)]);
    expect(loose.passOption?.kind, OptionKind.pass);
    expect(loose.passOption?.dice, [0]);
  });
}
