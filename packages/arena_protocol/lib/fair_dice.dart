/// Provably fair dice (README section 11, docs/contracts/protocol.md).
///
/// The server commits to a secret seed by publishing its SHA-256 hash before
/// any client seed is known. Every roll is derived from the seed, the joined
/// client seeds and the roll number, and the seed is revealed at game over.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Length of a server seed in bytes.
const int kServerSeedLength = 32;

/// Longest allowed client seed.
const int kMaxClientSeedLength = 64;

final RegExp _clientSeedPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Whether [seed] is a valid client seed: 1 to 64 of `A-Z a-z 0-9 _ -`.
bool isValidClientSeed(String seed) => _clientSeedPattern.hasMatch(seed);

/// A fresh 32 byte server seed from a secure random source.
Uint8List generateServerSeed([Random? random]) {
  final rng = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(kServerSeedLength, (_) => rng.nextInt(256)),
  );
}

/// Lowercase hex of [bytes].
String toHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Bytes of a hex string. Throws [FormatException] on bad input.
Uint8List fromHex(String hex) {
  if (hex.length.isOdd) throw FormatException('odd length hex', hex);
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) throw FormatException('bad hex', hex);
    out[i] = v;
  }
  return out;
}

/// `hex(sha256(serverSeed))`, lowercase.
String hashServerSeed(List<int> serverSeed) =>
    sha256.convert(serverSeed).toString();

/// The game's client seed: each seated player's seed in seat order, joined
/// with `:`. A player who sent none contributes their seat number (from 0).
String combineClientSeeds(List<String?> seedsInSeatOrder) {
  final parts = <String>[];
  for (var i = 0; i < seedsInSeatOrder.length; i++) {
    parts.add(seedsInSeatOrder[i] ?? '$i');
  }
  return parts.join(':');
}

/// The two dice for roll number [rollNumber] (the engine's rollNumber read
/// before applyRoll, starting at 0).
(int, int) rollDice(List<int> serverSeed, String clientSeed, int rollNumber) {
  final hmac = Hmac(sha256, serverSeed);
  final values = <int>[];
  for (var round = 0; values.length < 2; round++) {
    final message = round == 0
        ? '$clientSeed:$rollNumber'
        : '$clientSeed:$rollNumber:$round';
    final digest = hmac.convert(utf8.encode(message)).bytes;
    takeDice(digest, values);
  }
  return (values[0], values[1]);
}

/// Appends dice from [digest] to [values] until it holds two. Bytes of 252 or
/// more are skipped so every face is equally likely. Exposed for tests.
void takeDice(List<int> digest, List<int> values) {
  for (final b in digest) {
    if (values.length == 2) return;
    if (b >= 252) continue;
    values.add(b % 6 + 1);
  }
}

/// Checks that [serverSeedHex] matches [serverSeedHash] and that every roll in
/// [rolls] (rolls[i] is roll number i) comes from the seeds.
bool verifyRolls({
  required String serverSeedHex,
  required String serverSeedHash,
  required String clientSeed,
  required List<(int, int)> rolls,
}) {
  final Uint8List seed;
  try {
    seed = fromHex(serverSeedHex);
  } on FormatException {
    return false;
  }
  if (hashServerSeed(seed) != serverSeedHash.toLowerCase()) return false;
  for (var i = 0; i < rolls.length; i++) {
    if (rollDice(seed, clientSeed, i) != rolls[i]) return false;
  }
  return true;
}
