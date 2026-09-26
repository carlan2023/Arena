import 'package:arena/board/board_geometry.dart';
import 'package:arena/board/board_scene.dart';
import 'package:arena/board/piece_layout.dart';
import 'package:arena/game/move_planner.dart';
import 'package:arena/game/move_selection.dart';
import 'package:arena/game/table_view.dart';
import 'package:arena/ui/game_table.dart';
import 'package:arena/ui/seat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const yellow = PlayerColor.yellow;

class FakeActions implements TableActions {
  final log = <String>[];
  MoveOption? chosen;
  List<PieceRef>? tapped;

  @override
  void roll() => log.add('roll');
  @override
  void undo() => log.add('undo');
  @override
  void tapPieces(List<PieceRef> pieces) => tapped = pieces;
  @override
  void chooseOption(MoveOption option) => chosen = option;
}

const seats = [
  SeatView(color: red, name: 'Red', isYou: true),
  SeatView(color: yellow, name: 'Yellow', isBot: true),
];

Future<void> pumpTable(
  WidgetTester tester,
  TableView view,
  TableActions actions,
) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameTable(view: view, actions: actions),
      ),
    ),
  );
}

Offset boardPoint(WidgetTester tester, Offset p, int turns) {
  final box = tester.getRect(find.byType(BoardScene));
  return box.topLeft +
      BoardGeometry.rotatePoint(p, turns) *
          (box.width / BoardGeometry.gridSize);
}

void main() {
  testWidgets('fits a small phone and places cards at their corners', (
    tester,
  ) async {
    final view = TableView.of(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      seats: seats,
      canRoll: true,
      turns: BoardGeometry.viewTurnsFor(red.index),
    );
    final actions = FakeActions();
    await pumpTable(tester, view, actions);
    expect(tester.takeException(), isNull);
    expect(find.byType(SeatCard), findsNWidgets(2));
    expect(find.text('Red (you)'), findsOneWidget);

    // Your yard is bottom left, so your card is below the board on the left.
    final board = tester.getRect(find.byType(BoardScene));
    final you = tester.getCenter(find.byKey(const ValueKey('seat-red')));
    expect(you.dy, greaterThan(board.bottom));
    expect(you.dx, lessThan(board.center.dx));
    final them = tester.getCenter(find.byKey(const ValueKey('seat-yellow')));
    expect(them.dy, lessThan(board.top));
    expect(them.dx, greaterThan(board.center.dx));

    // The tray sits in the bottom third.
    expect(
      tester.getCenter(find.byKey(const Key('roll'))).dy,
      greaterThan(740 * 2 / 3),
    );
    await tester.tap(find.byKey(const Key('roll')));
    expect(actions.log, ['roll']);
  });

  testWidgets('tapping a piece and then a ghost reaches the actions', (
    tester,
  ) async {
    final rolled = applyRoll(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      6,
      3,
    );
    final sel = MoveSelection(rolled)..select([const PieceRef(red, 0)]);
    final view = TableView.of(rolled, seats: seats, selection: sel);
    final actions = FakeActions();
    await pumpTable(tester, view, actions);

    await tester.tapAt(
      boardPoint(tester, piecePoint(const PieceRef(red, 2), kAtHome), 0),
    );
    expect(actions.tapped, [const PieceRef(red, 2)]);

    final release = view.options.single;
    expect(release.kind, OptionKind.single);
    await tester.tapAt(
      boardPoint(tester, piecePoint(const PieceRef(red, 0), release.target), 0),
    );
    expect(actions.chosen, same(release));
  });

  testWidgets('the countdown ring shows for the active seat', (tester) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + 10000;
    final view = TableView.of(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      seats: seats,
      deadline: deadline,
    );
    await pumpTable(tester, view, FakeActions());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.5, 0.05));
  });
}
