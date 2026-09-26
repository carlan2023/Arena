import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_bots/ludo_bots.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_geometry.dart';
import 'bots.dart';
import 'dice.dart';
import 'move_planner.dart';
import 'move_selection.dart';
import 'table_view.dart';

/// Settings for a pass and play game on one phone.
class LocalGameConfig {
  const LocalGameConfig({
    required this.mode,
    required this.seats,
    this.rules = const RulesConfig(),
  });

  final GameMode mode;

  /// Seated colours in turn order, with who plays each.
  final Map<PlayerColor, SeatKind> seats;
  final RulesConfig rules;

  List<PlayerColor> get players =>
      PlayerColor.values.where(seats.containsKey).toList();
}

/// Timings, shortened in tests.
class LocalGameTimings {
  const LocalGameTimings({
    this.autoPlay = const Duration(milliseconds: 500),
    this.botRoll = const Duration(milliseconds: 1200),
    this.botMove = const Duration(milliseconds: 800),
  });

  /// README section 7: a forced sequence plays after half a second.
  final Duration autoPlay;
  final Duration botRoll;
  final Duration botMove;
}

final diceSourceProvider = Provider<DiceSource>((ref) => RandomDiceSource());

final localTimingsProvider = Provider<LocalGameTimings>(
  (ref) => const LocalGameTimings(),
);

final botProvider = Provider.family<LudoBot, SeatKind>(
  (ref, kind) => botForSeat(kind),
);

final localGameProvider = NotifierProvider.autoDispose
    .family<LocalGameController, TableView, LocalGameConfig>(
      LocalGameController.new,
    );

String colorName(PlayerColor c) =>
    c.name[0].toUpperCase() + c.name.substring(1);

/// Runs an offline game: humans take turns on one phone, bots play
/// themselves, dice come from [diceSourceProvider].
class LocalGameController extends Notifier<TableView> implements TableActions {
  LocalGameController(this.config);

  final LocalGameConfig config;

  late GameState _game;
  MoveSelection? _selection;
  String? _message;
  Timer? _timer;

  GameState get game => _game;

  @override
  TableView build() {
    _game = GameState.newGame(
      mode: config.mode,
      players: config.players,
      rules: config.rules,
    );
    ref.onDispose(() => _timer?.cancel());
    _schedule();
    return _view();
  }

  LocalGameTimings get _timings => ref.read(localTimingsProvider);

  SeatKind _kindOf(PlayerColor c) => config.seats[c] ?? SeatKind.human;

  bool get _humanTurn => _kindOf(_game.current) == SeatKind.human;

  List<SeatView> get _seats => [
    for (final c in config.players)
      SeatView(
        color: c,
        name: _kindOf(c) == SeatKind.human
            ? colorName(c)
            : '${colorName(c)} bot',
        isBot: _kindOf(c) != SeatKind.human,
      ),
  ];

  /// The first human's yard sits at the bottom left, as online (D24).
  int get _turns {
    final humans = config.players.where((c) => _kindOf(c) == SeatKind.human);
    final c = humans.isEmpty ? config.players.first : humans.first;
    return BoardGeometry.viewTurnsFor(c.index);
  }

  TableView _view() => TableView.of(
    _game,
    seats: _seats,
    selection: _humanTurn ? _selection : null,
    turns: _turns,
    canRoll:
        _humanTurn &&
        _selection == null &&
        _game.phase == TurnPhase.awaitingRoll,
    message: _message,
  );

  void _emit() => state = _view();

  @override
  void roll() {
    if (!_humanTurn ||
        _selection != null ||
        _game.phase != TurnPhase.awaitingRoll) {
      return;
    }
    _roll();
  }

  void _roll() {
    final (a, b) = ref.read(diceSourceProvider).roll();
    final roller = _game.current;
    final rolled = applyRoll(_game, a, b);
    _message = null;
    if (rolled.phase == TurnPhase.awaitingMove) {
      _game = rolled;
      _selection = MoveSelection(rolled);
      if (_humanTurn) {
        _scheduleForced();
      } else {
        _timer = Timer(_timings.botMove, _playBot);
      }
    } else {
      // No legal step: the engine already ended the roll.
      _game = rolled;
      _selection = null;
      _message = '${colorName(roller)} rolled $a and $b: no move possible';
      _schedule();
    }
    _emit();
  }

  @override
  void tapPieces(List<PieceRef> pieces) {
    final sel = _selection;
    if (sel == null || !_humanTurn) return;
    sel.select(pieces);
    _emit();
  }

  @override
  void chooseOption(MoveOption option) {
    final sel = _selection;
    if (sel == null || !_humanTurn) return;
    _timer?.cancel();
    sel.choose(option);
    _afterStep();
  }

  @override
  void undo() {
    final sel = _selection;
    if (sel == null || !_humanTurn) return;
    _timer?.cancel();
    if (sel.undo()) _scheduleForced();
    _emit();
  }

  void _afterStep() {
    final sel = _selection!;
    if (sel.rollEnded) {
      _commit(sel.state);
    } else {
      _scheduleForced();
      _emit();
    }
  }

  void _commit(GameState next) {
    _game = next;
    _selection = null;
    if (_game.phase == TurnPhase.gameOver) {
      final w = winners(_game) ?? const [];
      _message = w.isEmpty
          ? 'Game over'
          : '${w.map(colorName).join(' and ')} won';
    }
    _schedule();
    _emit();
  }

  void _scheduleForced() {
    _timer?.cancel();
    final rest = _selection?.forcedRest;
    if (rest == null) return;
    _timer = Timer(_timings.autoPlay, () {
      _selection!.playRest(rest);
      _commit(_selection!.state);
    });
  }

  /// Arms the next bot action, if a bot is to roll.
  void _schedule() {
    _timer?.cancel();
    if (_game.phase != TurnPhase.awaitingRoll || _humanTurn) return;
    _timer = Timer(_timings.botRoll, _roll);
  }

  void _playBot() {
    final sel = _selection;
    if (sel == null) return;
    final moves = ref
        .read(botProvider(_kindOf(_game.current)))
        .chooseMoves(sel.state);
    sel.playRest(moves);
    if (!sel.rollEnded) {
      // A bot must never stall the game; finish with any legal rest.
      final rest = legalSequences(sel.state);
      if (rest.isNotEmpty) sel.playRest(rest.first);
    }
    _commit(sel.state);
  }
}
