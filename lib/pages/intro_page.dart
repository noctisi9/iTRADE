import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

class IntroPage extends StatefulWidget {
  final VoidCallback onDone;
  const IntroPage({super.key, required this.onDone});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  static const _images = [
    'assets/intro/intro1.jpg',
    'assets/intro/intro2.jpg',
    'assets/intro/intro3.jpg',
    'assets/intro/intro4.jpg',
    'assets/intro/intro5.jpg',
    'assets/intro/intro6.jpg',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _images.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final headlineSize = (width * 0.16).clamp(48.0, 64.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
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
          // subtle top scrim so a status bar / future chrome stays legible
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.25), Colors.transparent],
                stops: const [0.0, 0.25],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
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
                  Text(
                    'Trading',
                    style: TextStyle(
                      fontSize: headlineSize,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                      color: AppColors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'made',
                    style: TextStyle(
                      fontSize: headlineSize,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                      color: AppColors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'simple.',
                    style: TextStyle(
                      fontSize: headlineSize,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                      color: AppColors.red,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Signals at your fingertips.',
                    style: TextStyle(fontSize: 15, color: AppColors.textDim),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: widget.onDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      child: const Text(
                        'ENTER',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 3),
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
