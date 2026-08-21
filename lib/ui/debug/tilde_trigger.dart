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