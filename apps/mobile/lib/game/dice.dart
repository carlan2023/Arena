import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';

/// Where offline games get their dice. Online games never roll on the phone.
abstract interface class DiceSource {
  (int, int) roll();
}

class RandomDiceSource implements DiceSource {
  RandomDiceSource([Random? random]) : _random = random ?? Random();

  final Random _random;

  @override
  (int, int) roll() => (_random.nextInt(6) + 1, _random.nextInt(6) + 1);
}

/// Plays back fixed rolls, for tests and the tutorial. Throws when empty.
class ScriptedDiceSource implements DiceSource {
  ScriptedDiceSource(Iterable<(int, int)> rolls) : _rolls = [...rolls];

  final List<(int, int)> _rolls;

  @override
  (int, int) roll() => _rolls.removeAt(0);
}

/// One die in the tray.
class DieFace {
  const DieFace(this.value, {required this.used});

  final int value;
  final bool used;

  @override
  bool operator ==(Object other) =>
      other is DieFace && other.value == value && other.used == used;

  @override
  int get hashCode => Object.hash(value, used);

  @override
  String toString() => used ? '($value)' : '$value';
}

/// The two dice of the last roll, marking the ones already spent. A die is
/// unused while its value is still in `remainingDice`; on a double the left
/// die is spent first.
List<DieFace> diceFaces(GameState state) {
  final left = [...state.remainingDice];
  final roll = state.lastRoll;
  final faces = [
    for (var i = roll.length - 1; i >= 0; i--)
      DieFace(roll[i], used: !left.remove(roll[i])),
  ];
  return faces.reversed.toList();
}
