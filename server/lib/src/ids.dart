import 'dart:math';

/// Characters allowed in room codes: no 0, O, 1, I or L.
const String kRoomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const int kRoomCodeLength = 6;

final RegExp _roomCodePattern = RegExp(
  '^[$kRoomCodeAlphabet]{$kRoomCodeLength}\$',
);

bool isValidRoomCode(String code) => _roomCodePattern.hasMatch(code);

String newRoomCode(Random random) => String.fromCharCodes([
  for (var i = 0; i < kRoomCodeLength; i++)
    kRoomCodeAlphabet.codeUnitAt(random.nextInt(kRoomCodeAlphabet.length)),
]);

/// A random UUID version 4.
String newUuid(Random random) {
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isUuid(String s) => _uuidPattern.hasMatch(s);
