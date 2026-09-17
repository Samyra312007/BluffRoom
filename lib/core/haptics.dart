import 'package:flutter/services.dart';

/// Haptic feedback helpers, safe no-ops on platforms without vibrators.
class Haptics {
  Haptics._();

  static void light() => HapticFeedback.selectionClick();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void success() => HapticFeedback.vibrate();
  static void warning() => HapticFeedback.heavyImpact();
}
