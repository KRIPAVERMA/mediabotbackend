import 'package:flutter/material.dart';

/// Animated progress steps widget shown during download.
class ProgressSteps extends StatelessWidget {
  final int currentStep; // 1-4

  const ProgressSteps({super.key, required this.currentStep});

  static const _steps = [
    ('🔗', 'Validating'),
    ('📥', 'Downloading'),
    ('🔄', 'Converting'),
    ('✅', 'Done'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          children: [
            // Header with pulsing dot
            Row(
              children: [
                _PulsingDot(),
                const SizedBox(width: 8),
                Text(
                  currentStep < 4 ? 'Processing…' : 'Complete!',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Step pills
            Row(
              children: List.generate(4, (i) {
                final step = i + 1;
                final isDone = step < currentStep;
                final isActive = step == currentStep;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isDone
                          ? const Color(0xFF34D399).withValues(alpha: 0.08)
                          : isActive
                              ? const Color(0xFFA78BFA).withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.02),
                      border: Border.all(
                        color: isDone
                            ? const Color(0xFF34D399).withValues(alpha: 0.25)
                            : isActive
                                ? const Color(0xFFA78BFA)
                                    .withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(_steps[i].$1,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          _steps[i].$2,
                          style: TextStyle(
                            fontSize: 9,
                            color: isDone
                                ? const Color(0xFF34D399)
                                : isActive
                                    ? const Color(0xFFA78BFA)
                                    : Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            // Indeterminate bar
            if (currentStep < 4) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(
                  backgroundColor: Color(0x15FFFFFF),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFFA78BFA)),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
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
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFA78BFA),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(0xFFA78BFA).withValues(alpha: 0.4 * _ctrl.value),
                blurRadius: 10 * _ctrl.value,
                spreadRadius: 2 * _ctrl.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
