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
  test('worked example 1: release with the 6, both dice go to 3', () {
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
    expect(both.single.target, 3);
    expect(both.single.dice, [6, 3]);
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

  test('both dice avoid an optional capture on the middle square (D24)', () {
    // Red at 10 rolls 3 and 5. A single green piece sits on square 13.
    final s = rolled(
      position({
        red: [10, kAtHome, kAtHome, kAtHome],
        green: [0, kAtHome, kAtHome, kAtHome],
      }),
      3,
      5,
    );
    final options = MovePlanner(s).optionsFor(const PieceRef(red, 0));
    final both = options.where((o) => o.kind == OptionKind.both).single;
    expect(both.target, 18);
    expect(both.moves, [Move.advance(red, 0, 5), Move.advance(red, 0, 3)]);
    final singles = {
      for (final o in options)
        if (o.kind == OptionKind.single) o.target,
    };
    expect(singles, {13, 15});
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
