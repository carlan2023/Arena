import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

void main() {
  test('README section 10 example', () {
    final p = computePayout(
      stakePerPlayer: 5000,
      players: 2,
      settings: const PayoutSettings(),
    );
    expect(p.pot, 10000);
    expect(p.rake, 1200);
    expect(p.grossToWinner, 8800);
    expect(p.netGain, 3800);
    expect(p.withheld, 570);
    expect(p.toWinner, 8230);
    expect(p.rakeTax, 360);
    expect(p.houseKeeps, 840);
  });

  test('defaults are 1200, 3000, 1500 basis points', () {
    const s = PayoutSettings();
    expect(s.rakeBasisPoints, 1200);
    expect(s.rakeTaxBasisPoints, 3000);
    expect(s.winningsWithholdingBasisPoints, 1500);
  });

  test('money always adds up, percentages floored', () {
    for (final stake in [1000, 2000, 5000, 10000, 20000, 50000, 1234]) {
      for (final players in [2, 3, 4]) {
        for (final rake in [1000, 1250, 1500]) {
          final p = computePayout(
            stakePerPlayer: stake,
            players: players,
            settings: PayoutSettings(rakeBasisPoints: rake),
          );
          expect(p.toWinner + p.withheld + p.rake, p.pot);
          expect(p.rakeTax + p.houseKeeps, p.rake);
          expect(p.rake, p.pot * rake ~/ 10000);
        }
      }
    }
    final odd = computePayout(
      stakePerPlayer: 1234,
      players: 2,
      settings: const PayoutSettings(),
    );
    expect(odd.rake, 296); // 296.16
    expect(odd.netGain, 938);
    expect(odd.withheld, 140); // 140.7
    expect(odd.rakeTax, 88); // 88.8
  });

  test('rejects fewer than 2 players or a negative stake', () {
    expect(
      () => computePayout(
        stakePerPlayer: 1000,
        players: 1,
        settings: const PayoutSettings(),
      ),
      throwsArgumentError,
    );
    expect(
      () => computePayout(
        stakePerPlayer: -1,
        players: 2,
        settings: const PayoutSettings(),
      ),
      throwsArgumentError,
    );
  });
}
