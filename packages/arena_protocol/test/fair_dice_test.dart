import 'dart:typed_data';

import 'package:arena_protocol/fair_dice.dart';
import 'package:test/test.dart';

void main() {
  // Seed bytes 0..31, client seed "alice:bob". Expected values were computed
  // independently with Python's hmac and hashlib.
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  const clientSeed = 'alice:bob';
  const expected = [
    (3, 3),
    (6, 1),
    (3, 3),
    (4, 2),
    (2, 5),
    (1, 1),
    (3, 4),
    (4, 3),
    (3, 6),
    (4, 2),
  ];

  test('hash of the fixed seed', () {
    expect(
      hashServerSeed(seed),
      '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd',
    );
  });

  test('known vector: first ten rolls', () {
    for (var n = 0; n < expected.length; n++) {
      expect(rollDice(seed, clientSeed, n), expected[n], reason: 'roll $n');
    }
  });

  test('verifyRolls accepts the known vector', () {
    expect(
      verifyRolls(
        serverSeedHex: toHex(seed),
        serverSeedHash: hashServerSeed(seed),
        clientSeed: clientSeed,
        rolls: expected,
      ),
      isTrue,
    );
  });

  test('verifyRolls rejects a changed roll, seed, hash or client seed', () {
    final hex = toHex(seed);
    final hash = hashServerSeed(seed);
    final changed = [...expected]..[4] = (2, 6);
    expect(
      verifyRolls(
        serverSeedHex: hex,
        serverSeedHash: hash,
        clientSeed: clientSeed,
        rolls: changed,
      ),
      isFalse,
    );
    expect(
      verifyRolls(
        serverSeedHex: '00$hex'.substring(0, 64),
        serverSeedHash: hash,
        clientSeed: clientSeed,
        rolls: expected,
      ),
      isFalse,
    );
    expect(
      verifyRolls(
        serverSeedHex: hex,
        serverSeedHash: hash,
        clientSeed: 'alice:eve',
        rolls: expected,
      ),
      isFalse,
    );
    expect(
      verifyRolls(
        serverSeedHex: 'zz',
        serverSeedHash: hash,
        clientSeed: clientSeed,
        rolls: const [],
      ),
      isFalse,
    );
  });

  test('takeDice skips bytes of 252 or more', () {
    final values = <int>[];
    takeDice([255, 252, 251, 0, 7], values);
    expect(values, [251 % 6 + 1, 1]);
  });

  test('takeDice continues across digests', () {
    final values = <int>[];
    takeDice(List.filled(31, 253) + [5], values);
    expect(values, [6]);
    takeDice([254, 12], values);
    expect(values, [6, 1]);
  });

  test('dice are uniform enough over many rolls', () {
    final counts = List.filled(7, 0);
    for (var n = 0; n < 6000; n++) {
      final (a, b) = rollDice(seed, clientSeed, n);
      counts[a]++;
      counts[b]++;
    }
    for (var face = 1; face <= 6; face++) {
      expect(counts[face], inInclusiveRange(1800, 2200));
    }
  });

  test('client seeds', () {
    expect(isValidClientSeed('abc_DEF-123'), isTrue);
    expect(isValidClientSeed(''), isFalse);
    expect(isValidClientSeed('a:b'), isFalse);
    expect(isValidClientSeed('x' * 64), isTrue);
    expect(isValidClientSeed('x' * 65), isFalse);
    expect(combineClientSeeds(['a', null, 'c']), 'a:1:c');
  });

  test('server seeds are 32 random bytes and hex round trips', () {
    final s = generateServerSeed();
    expect(s, hasLength(32));
    expect(fromHex(toHex(s)), s);
    expect(generateServerSeed(), isNot(s));
  });
}
