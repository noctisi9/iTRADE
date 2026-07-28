import 'package:flutter/material.dart';
import '../theme.dart';

class PulsingDot extends StatefulWidget {
  final double size;
  final Color color;
  const PulsingDot({super.key, this.size = 10, this.color = AppColors.red});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - t) * 0.5,
              child: Container(
                width: widget.size * (1 + t * 1.6),
                height: widget.size * (1 + t * 1.6),
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          ],
        );
      },
    );
  }
}
