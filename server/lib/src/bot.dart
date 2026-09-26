import 'dart:math';

import 'package:ludo_bots/ludo_bots.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'rooms/room_manager.dart';

/// The normal bot from packages/ludo_bots, used for timeout moves and bot
/// seats.
MoveChooser normalBotChooser([Random? random]) {
  final bot = botFor(BotLevel.normal, random: random);
  return (GameState state) => bot.chooseMoves(state);
}
