import 'package:flutter/material.dart';
import '../services/garden_calc.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ParticleLayer
// Ambient floating dots/orbs behind the indicator nodes.
// The 4 neutral grey corner orbs are purely decorative (unchanged).
// The colored dots are grouped per-indicator (AO / AC / STOCH) and react to
// that indicator's live strength: brighter + larger + denser when strong,
// dim + small when weak. Color is fixed per-indicator so it's always clear
// which cluster belongs to which node.
// ─────────────────────────────────────────────────────────────────────────────

class ParticleLayer extends StatefulWidget {
  final GardenResult? garden;
  const ParticleLayer({super.key, this.garden});

  @override
  State<ParticleLayer> createState() => _ParticleLayerState();
}

class _ParticleLayerState extends State<ParticleLayer>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  // Neutral ambient corner orbs — decorative only, untouched by data.
  static const _orbs = [
    _Particle(0.213, 0.213, 26, 0xFFEAEAEA, 5000, false),
    _Particle(0.787, 0.213, 30, 0xFFEAEAEA, 6000, true),
    _Particle(0.213, 0.787, 32, 0xFFEAEAEA, 5500, true),
    _Particle(0.787, 0.787, 26, 0xFFEAEAEA, 4500, false),
  ];

  // Indicator-linked dot clusters — positioned near their tomoe node.
  // AO cluster (cyan) sits near top, STOCH (red) near bottom-right,
  // AC (purple) near bottom-left — same corners as the old 4-color layout,
  // just re-tagged per indicator instead of per fixed corner.
  static const _aoSlots    = [_Particle(0.300, 0.123, 8, 0xFF66E6FF, 3000, false),
                              _Particle(0.700, 0.147, 11, 0xFF66E6FF, 4000, true)];
  static const _stochSlots = [_Particle(0.858, 0.318, 8, 0xFFFF7474, 3200, true),
                              _Particle(0.877, 0.700, 14, 0xFFFF7474, 4200, false)];
  static const _acSlots    = [_Particle(0.318, 0.877, 8, 0xFFE379FF, 3800, false),
                              _Particle(0.140, 0.700, 14, 0xFFE379FF, 5000, true)];

  List<_Particle> get _all => [..._orbs, ..._aoSlots, ..._stochSlots, ..._acSlots];

  @override
  void initState() {
    super.initState();
    final particles = _all;
    _ctrls = List.generate(particles.length, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: particles[i].durationMs),
      );
      if (particles[i].reverseStart) {
        ctrl.value = 1.0;
        ctrl.repeat(reverse: true);
      } else {
        ctrl.repeat(reverse: true);
      }
      return ctrl;
    });
    _anims = List.generate(
      particles.length,
      (i) => CurvedAnimation(parent: _ctrls[i], curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  // 0.0 (weak) .. 1.0 (strong) per indicator, from live GardenResult.
  double get _aoStrength    => ((widget.garden?.aoPct ?? 0) / 100).clamp(0.0, 1.0);
  double get _acStrength    => ((widget.garden?.acPct ?? 0) / 100).clamp(0.0, 1.0);
  double get _stochStrength => (((widget.garden?.stochK ?? 50) - 50).abs() / 50).clamp(0.0, 1.0);

  double _strengthFor(int index, int orbCount, int aoCount, int stochCount) {
    if (index < orbCount) return 1.0; // neutral orbs — always full, undimmed
    final i = index - orbCount;
    if (i < aoCount) return _aoStrength;
    final j = i - aoCount;
    if (j < stochCount) return _stochStrength;
    return _acStrength;
  }

  @override
  Widget build(BuildContext context) {
    final particles = _all;
    final orbCount   = _orbs.length;
    final aoCount    = _aoSlots.length;
    final stochCount = _stochSlots.length;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      return Stack(
        clipBehavior: Clip.none,
        children: List.generate(particles.length, (i) {
          final p = particles[i];
          final strength = _strengthFor(i, orbCount, aoCount, stochCount);
          final isOrb = i < orbCount;

          // Weak signal → dim + small. Strong signal → bright + large.
          final opacity = isOrb ? 0.70 : 0.20 + strength * 0.65;
          final sizeMul = isOrb ? 1.0 : 0.55 + strength * 0.75;

          return AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) {
              final t  = _anims[i].value;
              final dx = 4.0 * t;
              final dy = -4.0 * t;
              final sz = p.size.toDouble() * sizeMul;
              return Positioned(
                left: w * p.relX - sz / 2 + dx,
                top: h * p.relY - sz / 2 + dy,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: opacity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: sz,
                    height: sz,
                    decoration: BoxDecoration(
                      color: Color(p.color),
                      shape: BoxShape.circle,
                      boxShadow: (!isOrb && strength > 0.5)
                          ? [BoxShadow(
                              color: Color(p.color).withValues(alpha: 0.5 * strength),
                              blurRadius: 6 * strength,
                              spreadRadius: 1)]
                          : null,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Immutable particle descriptor
// ─────────────────────────────────────────────────────────────────────────────
class _Particle {
  final double relX;       // fractional position in parent (0-1)
  final double relY;
  final int size;          // base diameter px (before strength scaling)
  final int color;         // ARGB
  final int durationMs;
  final bool reverseStart; // whether to start the animation from 1.0

  const _Particle(
    this.relX,
    this.relY,
    this.size,
    this.color,
    this.durationMs,
    this.reverseStart,
  );
}
