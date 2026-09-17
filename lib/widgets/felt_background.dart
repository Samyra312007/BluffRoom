import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Full-bleed green felt background with vignette.
class FeltBackground extends StatelessWidget {
  const FeltBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.4,
          colors: [AppTheme.feltLight, AppTheme.felt, AppTheme.feltDark],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.feltEdge, width: 6),
          gradient: const RadialGradient(
            radius: 1.1,
            colors: [Colors.transparent, Colors.transparent, Color(0x66000000)],
            stops: [0.0, 0.7, 1.0],
          ),
        ),
        child: child,
      ),
    );
  }
}
