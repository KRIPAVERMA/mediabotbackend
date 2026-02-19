import 'package:flutter/material.dart';

/// Three bouncing dots typing indicator.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _dot(int index) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final delay = index * 0.2;
        final t = (_ctrl.value - delay).clamp(0.0, 1.0);
        final scale = 0.5 + 0.5 * (t < 0.5 ? t * 2 : (1 - t) * 2);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFA78BFA).withValues(alpha: scale),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_dot(0), const SizedBox(width: 4), _dot(1), const SizedBox(width: 4), _dot(2)],
    );
  }
}
