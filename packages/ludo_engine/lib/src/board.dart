import 'game_state.dart';

/// Seat colours in clockwise order.
enum PlayerColor { red, green, yellow, blue }

const int kTrackLength = 52;
const int kHomeColumnLength = 5;
const int kAtHome = -1;
const int kLastTrackProgress = 51;
const int kFinished = 57;
const int kPiecesPerPlayer = 4;

/// Absolute track square of [color]'s start square.
int startSquare(PlayerColor color) => color.index * 13;

/// Absolute track square (0..51) for a piece of [color] at [progress],
/// or null when the piece is not on the shared track.
int? trackSquare(PlayerColor color, int progress) {
  if (progress < 0 || progress > kLastTrackProgress) return null;
  return (startSquare(color) + progress) % kTrackLength;
}

/// The partner seat in teams mode (red with yellow, green with blue), else null.
PlayerColor? partnerOf(PlayerColor color, GameMode mode) {
  if (mode != GameMode.teams) return null;
  return PlayerColor.values[(color.index + 2) % 4];
}
