import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_tutorial/ludo_tutorial.dart';
import 'package:test/test.dart';

const red = PlayerColor.red;
const yellow = PlayerColor.yellow;

TutorialLesson lesson(String id) =>
    tutorialLessons().singleWhere((l) => l.id == id);

/// Plays a lesson's script with the suggested moves, checking each step.
GameState playThrough(TutorialLesson l) {
  var s = l.start;
  for (final step in l.steps) {
    expect(s.phase, TurnPhase.awaitingRoll);
    if (step.isPlayerStep) {
      expect(s.current, red);
      expect(step.check(s, step.suggested), const TutorialCheck.ok());
      expect(step.suggestedFor(s), step.suggested);
      var t = step.rolled(s);
      for (final m in step.suggested) {
        t = apply(t, m);
      }
      expect(sameBoard(t, step.expected!), isTrue);
      s = t;
    } else {
      expect(s.current, yellow);
      s = step.playBot(s);
    }
  }
  return s;
}

/// Plays a lesson up to (not including) step [index].
GameState before(TutorialLesson l, int index) {
  var s = l.start;
  for (final step in l.steps.take(index)) {
    s = step.isPlayerStep ? step.expected! : step.playBot(s);
  }
  return s;
}

void main() {
  test('five lessons in the documented order', () {
    expect(tutorialLessons().map((l) => l.id), [
      'release',
      'combine',
      'block',
      'break_block',
      'exact_finish',
    ]);
  });

  test('every lesson is oneVsOne, red against yellow, default rules', () {
    for (final l in tutorialLessons()) {
      expect(l.start.mode, GameMode.oneVsOne);
      expect(l.start.players, [red, yellow]);
      expect(l.start.current, red);
      expect(l.start.rules, const RulesConfig());
      expect(l.steps.first.isPlayerStep, isTrue);
      for (final step in l.steps) {
        if (step.isPlayerStep) {
          expect(step.suggested, isNotEmpty);
          expect(step.botMoves, isNull);
        } else {
          expect(step.suggested, isEmpty);
          expect(step.expected, isNull);
        }
      }
    }
  });

  test('text keys are unique, complete and used', () {
    expect(kTutorialTextKeys.toSet(), hasLength(kTutorialTextKeys.length));
    final used = <String>{
      for (final l in tutorialLessons()) ...[
        l.titleKey,
        l.introKey,
        for (final s in l.steps) s.hintKey,
      ],
    };
    expect(used, kTutorialTextKeys.toSet());
    for (final k in kTutorialTextKeys) {
      expect(k, matches(RegExp(r'^[a-z][A-Za-z0-9]*$')), reason: k);
    }
  });

  test('release: a 6 brings a piece out and the 3 moves it', () {
    final end = playThrough(lesson('release'));
    expect(end.pieces[red]!.where((p) => p == 3), hasLength(1));
  });

  test('combine: one piece moves 6 and captures', () {
    final l = lesson('combine');
    final s = before(l, 0);
    final step = l.steps[0];
    // Two single steps on the same piece reach the same board.
    expect(
      step.check(s, [Move.advance(red, 0, 2), Move.advance(red, 0, 4)]),
      const TutorialCheck.ok(),
    );
    // Splitting the dice between pieces is wrong.
    expect(
      step.check(s, [Move.advance(red, 0, 2), Move.advance(red, 1, 4)]),
      const TutorialCheck.wrong('tutorialCombineHint1'),
    );
    final end = playThrough(l);
    expect(end.pieces[red]![0], 16);
    expect(end.pieces[yellow]![0], kAtHome);
  });

  test('block: the 4 makes a block and yellow cannot pass it', () {
    final l = lesson('block');
    final afterPlayer = l.steps[0].expected!;
    expect(blocks(afterPlayer).single.square, 14);
    // Yellow behind the block has no move with 5 and 3.
    final yellowRoll = applyRoll(afterPlayer, 5, 3);
    expect(legalMoves(yellowRoll).where((m) => m.pieces.contains(0)), isEmpty);
    final end = playThrough(l);
    expect(blocks(end).single.pieces.map((p) => p.color), everyElement(red));
  });

  test('break_block: double 6 first, then the 5 captures the block', () {
    final l = lesson('break_block');
    final s = before(l, 0);
    expect(hasBlockRights(applyRoll(s, 6, 6), red, 2), isFalse);
    expect(
      l.steps[0].check(s, [Move.release(red, 1), Move.advance(red, 1, 6)]),
      const TutorialCheck.wrong('tutorialBreakBlockHint1'),
    );
    final end = playThrough(l);
    expect(end.pieces[yellow], everyElement(kAtHome));
    expect(end.pieces[red]![0], 20);
  });

  test(
    'exact_finish: the 5 cannot finish, the 2 and later the exact count do',
    () {
      final l = lesson('exact_finish');
      final s = before(l, 0);
      final rolled = l.steps[0].rolled(s);
      expect(legalMoves(rolled), isNot(contains(Move.advance(red, 0, 5))));
      expect(
        l.steps[0].check(s, [Move.combined(red, 1, 5, 2)]),
        const TutorialCheck.wrong('tutorialExactFinishHint1'),
      );
      final end = playThrough(l);
      expect(end.pieces[red]![0], kFinished);
    },
  );

  group('TutorialStep', () {
    final l = lesson('release');
    final player = l.steps[0];
    final bot = l.steps[1];

    test('accepts the rolled state as well as the state before the roll', () {
      final rolled = player.rolled(l.start);
      expect(rolled.phase, TurnPhase.awaitingMove);
      expect(player.rolled(rolled), same(rolled));
      expect(player.accepts(rolled, player.suggested), isTrue);
    });

    test('incomplete, illegal or extra moves are rejected', () {
      expect(player.accepts(l.start, [Move.release(red, 0)]), isFalse);
      expect(player.accepts(l.start, [Move.advance(red, 0, 3)]), isFalse);
      expect(
        player.accepts(l.start, [...player.suggested, Move.release(red, 1)]),
        isFalse,
      );
    });

    test('any piece number may be released', () {
      final other = [Move.release(red, 2), Move.advance(red, 2, 3)];
      expect(player.accepts(l.start, other), isTrue);
      // The canonical suggestion stays valid for the rolled state.
      final s = player.rolled(l.start);
      expect(player.suggestedFor(s), player.suggested);
    });

    test('suggestedFor finds another sequence when piece numbers moved', () {
      final c = lesson('combine');
      final step = c.steps[0];
      // Swap red's pieces so piece 0 is the far one.
      final s = before(c, 0);
      final swapped = s.copyWith(
        pieces: {
          ...s.pieces,
          red: [30, 10, kAtHome, kAtHome],
        },
      );
      final seq = step.suggestedFor(swapped);
      expect(seq, isNotEmpty);
      expect(seq, isNot(step.suggested));
      expect(step.accepts(swapped, seq), isTrue);
    });

    test('suggestedFor is empty when the expected board is out of reach', () {
      final c = lesson('combine');
      final s = before(c, 0);
      final moved = s.copyWith(
        pieces: {
          ...s.pieces,
          red: [40, 41, kAtHome, kAtHome],
        },
      );
      expect(c.steps[0].suggestedFor(moved), isEmpty);
    });

    test('bot steps', () {
      expect(bot.isPlayerStep, isFalse);
      expect(bot.accepts(l.start, const []), isFalse);
      expect(bot.suggestedFor(l.start), isEmpty);
      expect(() => player.playBot(l.start), throwsStateError);
    });

    test('TutorialCheck value semantics', () {
      expect(const TutorialCheck.ok().ok, isTrue);
      expect(const TutorialCheck.wrong('x').hintKey, 'x');
      expect(const TutorialCheck.ok().toString(), 'TutorialCheck.ok');
      expect(
        const TutorialCheck.wrong('x').hashCode,
        const TutorialCheck.wrong('x').hashCode,
      );
      expect(const TutorialCheck.wrong('x').toString(), contains('x'));
    });

    test('sameBoard ignores piece numbers but not squares or turn', () {
      final a = l.start;
      final b = a.copyWith(
        pieces: {
          ...a.pieces,
          yellow: [kAtHome, kAtHome, 5, kAtHome],
        },
      );
      expect(sameBoard(a, b), isTrue);
      expect(sameBoard(a, a.copyWith(current: yellow)), isFalse);
      expect(
        sameBoard(
          a,
          a.copyWith(
            pieces: {
              ...a.pieces,
              red: [0, kAtHome, kAtHome, kAtHome],
            },
          ),
        ),
        isFalse,
      );
      final three = GameState.custom(
        mode: GameMode.freeForAll,
        players: const [red, PlayerColor.green, yellow],
      );
      expect(sameBoard(a, three), isFalse);
    });
  });
}
