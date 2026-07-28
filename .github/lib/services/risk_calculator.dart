// ─────────────────────────────────────────────────────────────────────────────
// risk_calculator.dart — position sizing math
//
// Given account balance, risk % per trade, and stop loss in points, computes
// the lot size that keeps the loss on a stopped-out trade at exactly the
// risked amount.
//
// BOOM/CRASH point value: $0.50 per point at 0.20 lot (same constant used
// throughout the journal for P&L estimates) → $2.50 per point per 1.00 lot.
// ─────────────────────────────────────────────────────────────────────────────

class RiskCalcResult {
  final double riskAmount;      // $ at risk this trade
  final double recommendedLot;  // lot size to use
  final double dollarPerPoint;  // $ value of 1 point at the recommended lot
  final double potentialLoss;   // $ loss if stop is hit (should ≈ riskAmount)

  const RiskCalcResult({
    required this.riskAmount,
    required this.recommendedLot,
    required this.dollarPerPoint,
    required this.potentialLoss,
  });
}

class RiskCalculator {
  // $ per point at 1.00 lot for BOOM/CRASH (all variants use the same
  // point-value convention already used in journal_db.dart's estimatedPnl:
  // 0.5 * 0.20 = $0.10 per point at 0.20 lot → $0.50 per point per 1.00 lot).
  static const double _dollarPerPointPerLot = 0.5;

  /// [balance]        account balance in $
  /// [riskPct]        risk per trade, e.g. 1.0 for 1%
  /// [stopLossPoints] distance to stop loss, in points
  static RiskCalcResult compute({
    required double balance,
    required double riskPct,
    required double stopLossPoints,
  }) {
    final riskAmount = balance * (riskPct / 100);

    if (stopLossPoints <= 0) {
      return RiskCalcResult(
        riskAmount: riskAmount,
        recommendedLot: 0,
        dollarPerPoint: 0,
        potentialLoss: 0,
      );
    }

    // riskAmount = stopLossPoints * dollarPerPointPerLot * lot
    // → lot = riskAmount / (stopLossPoints * dollarPerPointPerLot)
    final rawLot = riskAmount / (stopLossPoints * _dollarPerPointPerLot);

    // Round down to nearest 0.01 lot (standard Deriv lot step) — never
    // round up, since that would risk more than requested.
    final lot = (rawLot * 100).floor() / 100;
    final dollarPerPoint = lot * _dollarPerPointPerLot;
    final potentialLoss  = dollarPerPoint * stopLossPoints;

    return RiskCalcResult(
      riskAmount: riskAmount,
      recommendedLot: lot,
      dollarPerPoint: dollarPerPoint,
      potentialLoss: potentialLoss,
    );
  }
}
