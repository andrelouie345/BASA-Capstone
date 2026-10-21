// lib/ui/debug/tilde_trigger.dart
import 'package:flutter/services.dart';

class TripleTildeDetector {
  final void Function() onTriggered;
  final Duration window;
  final List<DateTime> _presses = [];

  TripleTildeDetector({
    required this.onTriggered,
    this.window = const Duration(milliseconds: 700),
  });

  void handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey != LogicalKeyboardKey.backquote) return;

    final now = DateTime.now();
    _presses.add(now);
    _presses.removeWhere((t) => now.difference(t) > window);

    if (_presses.length >= 3) {
      _presses.clear();
      onTriggered();
    }
  }
}

/// Mobile counterpart of [TripleTildeDetector]: phones have no hardware
/// keyboard, so the console opens with [taps] quick taps in the top-left
/// corner instead. Fed raw pointer-down positions so it never takes the tap
/// away from whatever widget sits in that corner.
class CornerTapDetector {
  final void Function() onTriggered;
  final int taps;
  final double cornerSize;
  final Duration window;
  final List<DateTime> _presses = [];

  CornerTapDetector({
    required this.onTriggered,
    this.taps = 5,
    this.cornerSize = 60,
    this.window = const Duration(seconds: 2),
  });

  void handlePointerDown(Offset globalPosition) {
    if (globalPosition.dx > cornerSize || globalPosition.dy > cornerSize) {
      _presses.clear();
      return;
    }

    final now = DateTime.now();
    _presses.add(now);
    _presses.removeWhere((t) => now.difference(t) > window);

    if (_presses.length >= taps) {
      _presses.clear();
      onTriggered();
    }
  }
}
