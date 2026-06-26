import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IntroPage v2 — swipe-to-enter replaces the tap button
// The user drags a red pill rightward to fill the track and enter the app.
// Auto-crossfading background images every 3.5 s.
// ─────────────────────────────────────────────────────────────────────────────

class IntroPage extends StatefulWidget {
  final VoidCallback onDone;
  const IntroPage({super.key, required this.onDone});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> with TickerProviderStateMixin {
  static const _images = [
    'assets/intro/intro1.jpg',
    'assets/intro/intro2.jpg',
    'assets/intro/intro3.jpg',
    'assets/intro/intro4.jpg',
    'assets/intro/intro5.jpg',
  ];

  int _index = 0;
  Timer? _timer;

  // Swipe state
  double _dragX = 0;
  static const double _trackW = 280;
  static const double _pillW  = 64;
  static const double _maxDrag = _trackW - _pillW - 8; // 8px end gap
  bool _triggered = false;

  // Shimmer animation on the track label
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _images.length);
    });
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_triggered) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0.0, _maxDrag);
    });
    if (_dragX >= _maxDrag - 2) _complete();
  }

  void _onDragEnd(DragEndDetails _) {
    if (_triggered) return;
    setState(() => _dragX = 0);
  }

  void _complete() {
    if (_triggered) return;
    _triggered = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final width   = MediaQuery.of(context).size.width;
    final headSz  = (width * 0.16).clamp(48.0, 64.0);
    final fillPct = _dragX / _maxDrag;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background crossfade
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Image.asset(
              _images[_index],
              key: ValueKey(_index),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // Top scrim
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25],
              ),
            ),
          ),

          // Bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 48),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Headline
                  Text('Trading',
                      style: TextStyle(
                        fontSize: headSz,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        color: AppColors.black,
                        letterSpacing: -1,
                      )),
                  Text('made',
                      style: TextStyle(
                        fontSize: headSz,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        color: AppColors.black,
                        letterSpacing: -1,
                      )),
                  Text('simple.',
                      style: TextStyle(
                        fontSize: headSz,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        color: AppColors.red,
                        letterSpacing: -1,
                      )),
                  const SizedBox(height: 12),
                  const Text('Signals at your fingertips.',
                      style: TextStyle(fontSize: 15, color: AppColors.textDim)),
                  const SizedBox(height: 32),

                  // Swipe-to-enter track
                  Center(
                    child: SizedBox(
                      width: _trackW,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Track background
                          Container(
                            width: _trackW,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppColors.redFaint,
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),

                          // Fill bar
                          AnimatedContainer(
                            duration: Duration.zero,
                            width: _pillW + _dragX + 4,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(
                                  alpha: 0.10 + fillPct * 0.12),
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),

                          // Track label (shimmer)
                          Positioned.fill(
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _shimmerCtrl,
                                builder: (_, __) {
                                  final shimPct = (_shimmerCtrl.value * 2 - 1)
                                      .clamp(-1.0, 1.0);
                                  return Opacity(
                                    opacity: (0.4 + (1 - fillPct) * 0.6)
                                        .clamp(0.0, 1.0),
                                    child: ShaderMask(
                                      shaderCallback: (bounds) =>
                                          LinearGradient(
                                        begin: Alignment(shimPct - 0.4, 0),
                                        end: Alignment(shimPct + 0.4, 0),
                                        colors: [
                                          AppColors.red,
                                          Colors.red.shade200,
                                          AppColors.red,
                                        ],
                                      ).createShader(bounds),
                                      child: const Text(
                                        'SWIPE TO ENTER',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 3,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          // Draggable red pill
                          Positioned(
                            left: 4 + _dragX,
                            child: GestureDetector(
                              onHorizontalDragUpdate: _onDragUpdate,
                              onHorizontalDragEnd: _onDragEnd,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 80),
                                width: _pillW,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.red.withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
