import 'package:flutter/material.dart';

import '../models/card.dart';
import '../core/theme.dart';

/// Renders a single card face (or the back when [card] is null).
class PlayingCardView extends StatelessWidget {
  const PlayingCardView({
    super.key,
    this.card,
    this.selected = false,
    this.width = 62,
    this.onTap,
    this.elevated = false,
  });

  /// Null renders the face-down back design.
  final PlayingCard? card;
  final bool selected;
  final double width;
  final VoidCallback? onTap;

  /// Slight lift (e.g. current play indicator).
  final bool elevated;

  static const double _aspect = 0.72; // width / height

  @override
  Widget build(BuildContext context) {
    final height = width / _aspect;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: width,
        height: height,
        transform: Matrix4.translationValues(0, selected ? -14 : (elevated ? -6 : 0), 0),
        decoration: BoxDecoration(
          color: card == null ? AppTheme.feltDark : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppTheme.gold : (card == null ? AppTheme.feltEdge : const Color(0xFFD8D3C4)),
            width: selected ? 2.6 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected || elevated ? 0.45 : 0.3),
              blurRadius: selected ? 10 : 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: card == null ? _back() : _face(),
      ),
    );
  }

  Widget _back() {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5A40), Color(0xFF0B3D2E)],
        ),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5), width: 1),
      ),
      child: const Center(
        child: Text('♠', style: TextStyle(fontSize: 20, color: AppTheme.gold)),
      ),
    );
  }

  Widget _face() {
    final c = card!;
    final color = c.isRedSuit ? AppTheme.red : AppTheme.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              c.rankLabel,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.0,
              ),
            ),
          ),
          Text(
            c.suitSymbol,
            style: TextStyle(color: color, fontSize: width * 0.42, height: 1.0),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Transform.rotate(
              angle: 3.14159,
              child: Text(
                c.rankLabel,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small face-down card used to depict the pile.
class PileStackView extends StatelessWidget {
  const PileStackView({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = count.clamp(0, 5);
    return SizedBox(
      width: 74,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < shown; i++)
            Transform.translate(
              offset: Offset(i * -2.2, i * -2.6),
              child: const PlayingCardView(card: null, width: 62),
            ),
          if (shown == 0)
            Container(
              width: 62,
              height: 62 / 0.72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white24, width: 1.4),
              ),
              child: const Center(
                child: Text('PILE', style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2)),
              ),
            ),
        ],
      ),
    );
  }
}
