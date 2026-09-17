import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Circular countdown ring for the current turn.
class TurnTimerRing extends StatelessWidget {
  const TurnTimerRing({super.key, required this.secondsLeft, required this.totalSeconds});

  final int secondsLeft;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final total = totalSeconds <= 0 ? 30 : totalSeconds;
    final fraction = (secondsLeft / total).clamp(0.0, 1.0);
    final urgent = secondsLeft <= 10 && secondsLeft > 0;

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(46, 46),
            painter: _RingPainter(
              fraction: fraction,
              color: urgent ? AppTheme.red : AppTheme.gold,
            ),
          ),
          Text(
            '$secondsLeft',
            style: TextStyle(
              color: urgent ? AppTheme.red : AppTheme.cream,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white24;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      -2 * math.pi * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}
