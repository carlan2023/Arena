class PayoutSettings {
  /// Our share of the pot. 1200 is 12 percent.
  final int rakeBasisPoints;

  /// Tax on our share.
  final int rakeTaxBasisPoints;

  /// Withheld from the winner's net gain.
  final int winningsWithholdingBasisPoints;

  const PayoutSettings({
    this.rakeBasisPoints = 1200,
    this.rakeTaxBasisPoints = 3000,
    this.winningsWithholdingBasisPoints = 1500,
  });
}

class Payout {
  final int pot;
  final int rake;
  final int grossToWinner;
  final int netGain;
  final int withheld;
  final int toWinner;
  final int rakeTax;
  final int houseKeeps;

  const Payout({
    required this.pot,
    required this.rake,
    required this.grossToWinner,
    required this.netGain,
    required this.withheld,
    required this.toWinner,
    required this.rakeTax,
    required this.houseKeeps,
  });
}

int _percent(int amount, int basisPoints) => amount * basisPoints ~/ 10000;

/// README section 10. Every percentage is floored to whole UGX.
Payout computePayout({
  required int stakePerPlayer,
  required int players,
  required PayoutSettings settings,
}) {
  if (stakePerPlayer < 0) {
    throw ArgumentError.value(stakePerPlayer, 'stakePerPlayer');
  }
  if (players < 2) throw ArgumentError.value(players, 'players');
  final pot = stakePerPlayer * players;
  final rake = _percent(pot, settings.rakeBasisPoints);
  final grossToWinner = pot - rake;
  final netGain = grossToWinner - stakePerPlayer;
  final withheld = netGain > 0
      ? _percent(netGain, settings.winningsWithholdingBasisPoints)
      : 0;
  final rakeTax = _percent(rake, settings.rakeTaxBasisPoints);
  return Payout(
    pot: pot,
    rake: rake,
    grossToWinner: grossToWinner,
    netGain: netGain,
    withheld: withheld,
    toWinner: grossToWinner - withheld,
    rakeTax: rakeTax,
    houseKeeps: rake - rakeTax,
  );
}
