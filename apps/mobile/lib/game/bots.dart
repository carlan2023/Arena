import 'dart:math';

import 'package:ludo_bots/ludo_bots.dart';

/// Who sits in a seat of an offline game.
enum SeatKind { human, easyBot, normalBot }

/// The bot from packages/ludo_bots for a bot seat.
LudoBot botForSeat(SeatKind kind, {Random? random}) => switch (kind) {
  SeatKind.human => throw ArgumentError('humans choose for themselves'),
  SeatKind.easyBot => botFor(BotLevel.easy, random: random),
  SeatKind.normalBot => botFor(BotLevel.normal, random: random),
};
