import 'package:flutter/material.dart';

/// Animated floating gradient orbs for the background.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value;
        return Stack(
          children: [
            Positioned(
              top: -60 + 40 * t,
              left: -50 + 30 * t,
              child: _orb(320, const Color(0xFF7C3AED).withValues(alpha: 0.30)),
            ),
            Positioned(
              bottom: -80 + 50 * (1 - t),
              right: -40 + 20 * t,
              child: _orb(280, const Color(0xFFEC4899).withValues(alpha: 0.25)),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35 + 30 * (1 - t),
              left: MediaQuery.of(context).size.width * 0.3 - 20 * t,
              child: _orb(220, const Color(0xFF06B6D4).withValues(alpha: 0.20)),
            ),
          ],
        );
      },
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
