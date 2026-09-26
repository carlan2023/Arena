import 'package:arena/game/dice.dart';
import 'package:arena/ui/dice_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows both dice and marks the used one', (tester) async {
    await tester.pumpWidget(
      host(
        const DiceTray(
          dice: [DieFace(3, used: true), DieFace(5, used: false)],
          rollKey: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Die 3, used'), findsOneWidget);
    expect(find.bySemanticsLabel('Die 5'), findsOneWidget);
  });

  testWidgets('roll and undo are enabled only when allowed', (tester) async {
    var rolls = 0, undos = 0;
    Widget tray({bool roll = false, bool undo = false}) => host(
      DiceTray(
        dice: const [],
        rollKey: 0,
        canRoll: roll,
        canUndo: undo,
        onRoll: () => rolls++,
        onUndo: () => undos++,
      ),
    );
    await tester.pumpWidget(tray());
    await tester.tap(find.byKey(const Key('roll')));
    await tester.tap(find.byKey(const Key('undo')));
    expect((rolls, undos), (0, 0));

    await tester.pumpWidget(tray(roll: true, undo: true));
    await tester.tap(find.byKey(const Key('roll')));
    await tester.tap(find.byKey(const Key('undo')));
    expect((rolls, undos), (1, 1));
  });

  testWidgets('pass replaces roll when offered, and shows a message', (
    tester,
  ) async {
    var passes = 0;
    await tester.pumpWidget(
      host(
        DiceTray(
          dice: const [DieFace(2, used: true), DieFace(6, used: false)],
          rollKey: 2,
          canPass: true,
          message: 'Hello',
          onPass: () => passes++,
        ),
      ),
    );
    expect(find.byKey(const Key('roll')), findsNothing);
    await tester.tap(find.byKey(const Key('pass')));
    expect(passes, 1);
    expect(find.text('Hello'), findsOneWidget);
  });
}
