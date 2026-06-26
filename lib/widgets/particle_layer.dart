import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ParticleLayer
// Recreates the HTML's ambient floating dots and orbs that sit behind the
// four indicator nodes. Each particle uses its own staggered AnimationController
// so they float independently.
// ─────────────────────────────────────────────────────────────────────────────

class ParticleLayer extends StatefulWidget {
  const ParticleLayer({super.key});

  @override
  State<ParticleLayer> createState() => _ParticleLayerState();
}

class _ParticleLayerState extends State<ParticleLayer>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  // Particle definitions matching the HTML exactly
  // Each: (relX, relY, size, color, durationMs, reverseStart)
  static const _particles = [
    // Neutral grey orbs (orb-tl, orb-tr, orb-bl, orb-br)
    _Particle(0.213, 0.213, 26, 0xFFEAEAEA, 5000, false),
    _Particle(0.787, 0.213, 30, 0xFFEAEAEA, 6000, true),
    _Particle(0.213, 0.787, 32, 0xFFEAEAEA, 5500, true),
    _Particle(0.787, 0.787, 26, 0xFFEAEAEA, 4500, false),
    // Blue dots
    _Particle(0.300, 0.123, 8,  0xFF66E6FF, 3000, false),
    _Particle(0.700, 0.147, 11, 0xFF66E6FF, 4000, true),
    // Green dots
    _Particle(0.123, 0.300, 8,  0xFF65F87D, 3500, false),
    _Particle(0.140, 0.700, 14, 0xFF65F87D, 5000, true),
    // Red dots
    _Particle(0.858, 0.318, 8,  0xFFFF7474, 3200, true),
    _Particle(0.877, 0.700, 14, 0xFFFF7474, 4200, false),
    // Purple dots
    _Particle(0.318, 0.877, 8,  0xFFE379FF, 3800, false),
    _Particle(0.682, 0.865, 11, 0xFFE379FF, 4800, true),
  ];

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(_particles.length, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _particles[i].durationMs),
      );
      if (_particles[i].reverseStart) {
        ctrl.value = 1.0;
        ctrl.repeat(reverse: true);
      } else {
        ctrl.repeat(reverse: true);
      }
      return ctrl;
    });
    _anims = List.generate(
      _particles.length,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      return Stack(
        clipBehavior: Clip.none,
        children: List.generate(_particles.length, (i) {
          final p = _particles[i];
          return AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) {
              final t = _anims[i].value;
              final dx = 4.0 * t;
              final dy = -4.0 * t;
              return Positioned(
                left: w * p.relX - p.size / 2 + dx,
                top: h * p.relY - p.size / 2 + dy,
                child: Opacity(
                  opacity: 0.70,
                  child: Container(
                    width: p.size.toDouble(),
                    height: p.size.toDouble(),
                    decoration: BoxDecoration(
                      color: Color(p.color),
                      shape: BoxShape.circle,
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
  final int size;          // diameter px
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
