import 'package:ludo_engine/ludo_engine.dart';

import 'tutorial.dart';

const _red = PlayerColor.red;
const _yellow = PlayerColor.yellow;
const _home = kAtHome;
const _done = kFinished;

/// Yellow progress for an absolute track square.
int _y(int square) =>
    (square - startSquare(_yellow) + kTrackLength) % kTrackLength;

/// Every text key the lessons use. The app checks each exists in app_en.arb.
const List<String> kTutorialTextKeys = [
  'tutorialReleaseTitle',
  'tutorialReleaseIntro',
  'tutorialReleaseHint1',
  'tutorialReleaseBot1',
  'tutorialCombineTitle',
  'tutorialCombineIntro',
  'tutorialCombineHint1',
  'tutorialCombineBot1',
  'tutorialBlockTitle',
  'tutorialBlockIntro',
  'tutorialBlockHint1',
  'tutorialBlockBot1',
  'tutorialBreakBlockTitle',
  'tutorialBreakBlockIntro',
  'tutorialBreakBlockHint1',
  'tutorialBreakBlockHint2',
  'tutorialExactFinishTitle',
  'tutorialExactFinishIntro',
  'tutorialExactFinishHint1',
  'tutorialExactFinishBot1',
  'tutorialExactFinishHint2',
];

/// Builds a lesson by playing its script through the engine, so every step
/// is legal by construction and each player step knows its expected state.
class _Script {
  _Script(Map<PlayerColor, List<int>> pieces)
    : start = GameState.custom(
        mode: GameMode.oneVsOne,
        players: const [_red, _yellow],
        pieces: pieces,
        current: _red,
      ) {
    state = start;
  }

  final GameState start;
  late GameState state;
  final steps = <TutorialStep>[];

  void player(int d1, int d2, String hintKey, List<Move> moves) {
    var s = applyRoll(state, d1, d2);
    for (final m in moves) {
      s = apply(s, m);
    }
    steps.add(
      TutorialStep.player(
        roll: (d1, d2),
        hintKey: hintKey,
        suggested: moves,
        expected: s,
      ),
    );
    state = s;
  }

  void bot(int d1, int d2, String hintKey, List<Move> moves) {
    final step = TutorialStep.bot(
      roll: (d1, d2),
      hintKey: hintKey,
      botMoves: moves,
    );
    state = step.playBot(state);
    steps.add(step);
  }

  TutorialLesson lesson(String id, String keyStem) => TutorialLesson(
    id: id,
    titleKey: 'tutorial${keyStem}Title',
    introKey: 'tutorial${keyStem}Intro',
    start: start,
    steps: steps,
  );
}

/// The five lessons, in order: release, combine, block, break_block,
/// exact_finish. Red is the player, yellow is scripted, default rules.
List<TutorialLesson> tutorialLessons() => [
  _release(),
  _combine(),
  _block(),
  _breakBlock(),
  _exactFinish(),
];

// A 6 brings a piece out; the other die moves it.
TutorialLesson _release() {
  final s = _Script({
    _red: const [_home, _home, _home, _home],
    _yellow: [5, _home, _home, _home],
  });
  s.player(6, 3, 'tutorialReleaseHint1', [
    Move.release(_red, 0),
    Move.advance(_red, 0, 3),
  ]);
  s.bot(4, 2, 'tutorialReleaseBot1', [Move.combined(_yellow, 0, 4, 2)]);
  return s.lesson('release', 'Release');
}

// Both dice on one piece: 2 + 4 lands on the yellow piece 6 ahead.
TutorialLesson _combine() {
  final s = _Script({
    _red: const [10, 30, _home, _home],
    _yellow: [_y(16), _y(45), _home, _home],
  });
  s.player(2, 4, 'tutorialCombineHint1', [Move.combined(_red, 0, 2, 4)]);
  s.bot(1, 2, 'tutorialCombineBot1', [Move.combined(_yellow, 1, 1, 2)]);
  return s.lesson('combine', 'Combine');
}

// Land the 4 on your own piece to make a block; yellow behind it is stuck.
TutorialLesson _block() {
  final s = _Script({
    _red: const [10, 14, 30, _home],
    _yellow: [_y(11), _y(40), _home, _home],
  });
  s.player(4, 1, 'tutorialBlockHint1', [
    Move.advance(_red, 0, 4),
    Move.advance(_red, 2, 1),
  ]);
  s.bot(5, 3, 'tutorialBlockBot1', [Move.combined(_yellow, 1, 5, 3)]);
  return s.lesson('block', 'Block');
}

// A double 6 opens blocks for the rest of the turn: the extra roll's 5 lands
// on the yellow block and sends both pieces home.
TutorialLesson _breakBlock() {
  final s = _Script({
    _red: const [15, _home, _home, _home],
    _yellow: [_y(20), _y(20), _home, _home],
  });
  s.player(6, 6, 'tutorialBreakBlockHint1', [
    Move.release(_red, 1),
    Move.release(_red, 2),
  ]);
  s.player(5, 2, 'tutorialBreakBlockHint2', [
    Move.advance(_red, 0, 5),
    Move.advance(_red, 1, 2),
  ]);
  return s.lesson('break_block', 'BreakBlock');
}

// A piece 4 from the centre cannot use a 5; it finishes on an exact count.
TutorialLesson _exactFinish() {
  final s = _Script({
    _red: const [53, 20, _done, _done],
    _yellow: [10, _home, _home, _home],
  });
  s.player(5, 2, 'tutorialExactFinishHint1', [
    Move.advance(_red, 0, 2),
    Move.advance(_red, 1, 5),
  ]);
  s.bot(3, 3, 'tutorialExactFinishBot1', [Move.combined(_yellow, 0, 3, 3)]);
  s.player(2, 4, 'tutorialExactFinishHint2', [
    Move.advance(_red, 0, 2),
    Move.advance(_red, 1, 4),
  ]);
  return s.lesson('exact_finish', 'ExactFinish');
}
