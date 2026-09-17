import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/card.dart';
import '../models/game_events.dart';
import 'playing_card_view.dart';

/// Full-screen animated overlay shown while [ChallengeReveal] is active.
class ChallengeRevealOverlay extends StatefulWidget {
  const ChallengeRevealOverlay({
    super.key,
    required this.reveal,
    required this.onDismiss,
    this.autoDismissAfter = const Duration(seconds: 4),
  });

  final ChallengeReveal reveal;
  final VoidCallback onDismiss;
  final Duration autoDismissAfter;

  @override
  State<ChallengeRevealOverlay> createState() => _ChallengeRevealOverlayState();
}

class _ChallengeRevealOverlayState extends State<ChallengeRevealOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _c.forward();
    Timer(widget.autoDismissAfter, () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verdict = widget.reveal.wasBluff;
    final color = verdict ? AppTheme.red : AppTheme.success;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Material(
        color: Colors.black54,
        child: Center(
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flipping cards.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < widget.reveal.revealedCards.length; i++)
                  _FlipCard(index: i, controller: _c, card: widget.reveal.revealedCards[i]),
              ],
            ),
            const SizedBox(height: 20),
            // Verdict banner.
            ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: const Interval(0.5, 1.0, curve: Curves.elasticOut)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Text(
                  verdict ? 'BLUFF!' : 'TRUTHFUL',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.reveal.challengedName} was ${verdict ? "bluffing" : "telling the truth"}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.cream, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.reveal.collectorName} collects the pile',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.gold, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'challenged by ${widget.reveal.challengerName}',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({required this.index, required this.controller, required this.card});

  final int index;
  final AnimationController controller;
  final PlayingCard card; // resolved below via models import

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.12).clamp(0.0, 0.6);
    final flip = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: flip,
      builder: (context, _) {
        final t = flip.value.clamp(0.0, 1.0);
        // Simple flip illusion: scaleX from -1 to 1.
        final scale = (t * 2 - 1).abs().clamp(0.05, 1.0);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(t < 0.5 ? -scale : scale, 1, 1),
          child: Opacity(
            opacity: t < 0.5 ? 0.6 : 1.0,
            child: PlayingCardView(card: card, width: 58),
          ),
        );
      },
    );
  }
}
