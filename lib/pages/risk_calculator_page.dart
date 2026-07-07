import 'package:flutter/material.dart';
import '../services/risk_calculator.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RiskCalculatorPage
// Account balance + risk % + stop loss points → recommended lot size.
// Pure math, no network. Styled to match the rest of the app exactly
// (white/red theme, same card/border language as other pages).
// ─────────────────────────────────────────────────────────────────────────────

class RiskCalculatorPage extends StatefulWidget {
  const RiskCalculatorPage({super.key});

  @override
  State<RiskCalculatorPage> createState() => _RiskCalculatorPageState();
}

class _RiskCalculatorPageState extends State<RiskCalculatorPage> {
  final _balanceCtrl = TextEditingController(text: '100');
  final _riskCtrl    = TextEditingController(text: '1');
  final _slCtrl      = TextEditingController(text: '50');

  RiskCalcResult? _result;

  @override
  void initState() {
    super.initState();
    _recalc();
    _balanceCtrl.addListener(_recalc);
    _riskCtrl.addListener(_recalc);
    _slCtrl.addListener(_recalc);
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _riskCtrl.dispose();
    _slCtrl.dispose();
    super.dispose();
  }

  void _recalc() {
    final balance = double.tryParse(_balanceCtrl.text) ?? 0;
    final risk    = double.tryParse(_riskCtrl.text) ?? 0;
    final sl      = double.tryParse(_slCtrl.text) ?? 0;
    setState(() {
      _result = RiskCalculator.compute(
        balance: balance, riskPct: risk, stopLossPoints: sl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: const Text('Risk / Lot Calculator',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _field('Account balance ($)', _balanceCtrl),
          const SizedBox(height: 12),
          _field('Risk per trade (%)', _riskCtrl),
          const SizedBox(height: 12),
          _field('Stop loss (points)', _slCtrl),
          const SizedBox(height: 24),

          if (r != null) Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _row('Amount at risk', '\$${r.riskAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 10),
              _row('Recommended lot size',
                  r.recommendedLot.toStringAsFixed(2), big: true),
              const SizedBox(height: 10),
              _row('Value per point at this lot',
                  '\$${r.dollarPerPoint.toStringAsFixed(3)}'),
              const SizedBox(height: 10),
              _row('Loss if stop is hit',
                  '\$${r.potentialLoss.toStringAsFixed(2)}'),
              if (r.recommendedLot <= 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'Enter a stop loss distance greater than 0 to calculate lot size.',
                  style: TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 16),
          const Text(
            'Lot size is rounded down to the nearest 0.01 so you never risk '
            'more than the amount above. Point value assumes the standard '
            'BOOM/CRASH convention (\$0.50 per point at 1.00 lot).',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
          ),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool big = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
      Text(value, style: TextStyle(
          color: AppColors.red,
          fontWeight: FontWeight.w900,
          fontSize: big ? 22 : 15)),
    ]);
  }
}
