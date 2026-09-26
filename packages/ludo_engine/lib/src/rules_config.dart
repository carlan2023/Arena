/// One field per open rule R1 to R8 (README section 2). Defaults follow
/// docs/decisions.md D1 to D9.
class RulesConfig {
  const RulesConfig({
    this.tripleDoubleSixCancelsTurn = false,
    this.mustUseBothDice = true,
    this.blockMoveUsesSum = false,
    this.canContinuePastOwnBlock = false,
    this.countSixesAcrossTurn = true,
    this.freeForAllPlaysOn = true,
    this.teamWinsWhenBothFinish = true,
    this.partnersFormJointBlocks = false,
    this.finishedPlayerRollsForPartner = true,
  });

  /// R1: a third double 6 in a row ends the turn with no moves for that roll.
  final bool tripleDoubleSixCancelsTurn;

  /// R2: every step must keep the largest possible number of dice usable.
  final bool mustUseBothDice;

  /// R3: a block moves the sum of the double instead of one die value.
  final bool blockMoveUsesSum;

  /// R4: a piece that joined its own block may move again in the same roll.
  final bool canContinuePastOwnBlock;

  /// R5: the current roll's sixes count toward block rights.
  final bool countSixesAcrossTurn;

  /// R6: free for all continues after the first player finishes.
  final bool freeForAllPlaysOn;

  /// R7: a team wins only when both partners have finished.
  final bool teamWinsWhenBothFinish;

  /// R8 first half: partner pieces share squares and form joint blocks.
  final bool partnersFormJointBlocks;

  /// R8 second half: a finished player rolls for the partner.
  final bool finishedPlayerRollsForPartner;

  RulesConfig copyWith({
    bool? tripleDoubleSixCancelsTurn,
    bool? mustUseBothDice,
    bool? blockMoveUsesSum,
    bool? canContinuePastOwnBlock,
    bool? countSixesAcrossTurn,
    bool? freeForAllPlaysOn,
    bool? teamWinsWhenBothFinish,
    bool? partnersFormJointBlocks,
    bool? finishedPlayerRollsForPartner,
  }) => RulesConfig(
    tripleDoubleSixCancelsTurn:
        tripleDoubleSixCancelsTurn ?? this.tripleDoubleSixCancelsTurn,
    mustUseBothDice: mustUseBothDice ?? this.mustUseBothDice,
    blockMoveUsesSum: blockMoveUsesSum ?? this.blockMoveUsesSum,
    canContinuePastOwnBlock:
        canContinuePastOwnBlock ?? this.canContinuePastOwnBlock,
    countSixesAcrossTurn: countSixesAcrossTurn ?? this.countSixesAcrossTurn,
    freeForAllPlaysOn: freeForAllPlaysOn ?? this.freeForAllPlaysOn,
    teamWinsWhenBothFinish:
        teamWinsWhenBothFinish ?? this.teamWinsWhenBothFinish,
    partnersFormJointBlocks:
        partnersFormJointBlocks ?? this.partnersFormJointBlocks,
    finishedPlayerRollsForPartner:
        finishedPlayerRollsForPartner ?? this.finishedPlayerRollsForPartner,
  );

  List<bool> get _values => [
    tripleDoubleSixCancelsTurn,
    mustUseBothDice,
    blockMoveUsesSum,
    canContinuePastOwnBlock,
    countSixesAcrossTurn,
    freeForAllPlaysOn,
    teamWinsWhenBothFinish,
    partnersFormJointBlocks,
    finishedPlayerRollsForPartner,
  ];

  static const _keys = [
    'tripleDoubleSixCancelsTurn',
    'mustUseBothDice',
    'blockMoveUsesSum',
    'canContinuePastOwnBlock',
    'countSixesAcrossTurn',
    'freeForAllPlaysOn',
    'teamWinsWhenBothFinish',
    'partnersFormJointBlocks',
    'finishedPlayerRollsForPartner',
  ];

  Map<String, Object?> toJson() => {
    for (var i = 0; i < _keys.length; i++) _keys[i]: _values[i],
  };

  /// Missing keys take their defaults. Wrong types throw [FormatException].
  factory RulesConfig.fromJson(Map<String, Object?> json) {
    const d = RulesConfig();
    bool read(String key, bool fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is! bool) throw FormatException('RulesConfig.$key must be a bool');
      return v;
    }

    return RulesConfig(
      tripleDoubleSixCancelsTurn: read(
        'tripleDoubleSixCancelsTurn',
        d.tripleDoubleSixCancelsTurn,
      ),
      mustUseBothDice: read('mustUseBothDice', d.mustUseBothDice),
      blockMoveUsesSum: read('blockMoveUsesSum', d.blockMoveUsesSum),
      canContinuePastOwnBlock: read(
        'canContinuePastOwnBlock',
        d.canContinuePastOwnBlock,
      ),
      countSixesAcrossTurn: read(
        'countSixesAcrossTurn',
        d.countSixesAcrossTurn,
      ),
      freeForAllPlaysOn: read('freeForAllPlaysOn', d.freeForAllPlaysOn),
      teamWinsWhenBothFinish: read(
        'teamWinsWhenBothFinish',
        d.teamWinsWhenBothFinish,
      ),
      partnersFormJointBlocks: read(
        'partnersFormJointBlocks',
        d.partnersFormJointBlocks,
      ),
      finishedPlayerRollsForPartner: read(
        'finishedPlayerRollsForPartner',
        d.finishedPlayerRollsForPartner,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! RulesConfig) return false;
    final a = _values, b = other._values;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_values);

  @override
  String toString() => 'RulesConfig(${toJson()})';
}
