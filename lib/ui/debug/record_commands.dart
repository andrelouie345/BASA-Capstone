//lib/ui/debug/record_commands.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommandRecorder {
  final List<String> _commandHistory = [];
  int historyPointer = -1;

  void recordCommand(String command) {
    _commandHistory.add(command);
    historyPointer = _commandHistory.length -1;
 
  }

  List<String> get commandHistory => List.unmodifiable(_commandHistory);

    void handleKeyEvent(KeyEvent event, TextEditingController inputController) {
    if (event is! KeyDownEvent) return;
    if (_commandHistory.isEmpty) return;
    if (event.logicalKey != LogicalKeyboardKey.arrowUp && event.logicalKey != LogicalKeyboardKey.arrowDown) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (historyPointer < _commandHistory.length - 1){
        historyPointer++;
      }
    }else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (historyPointer > 0){
        historyPointer--;
      }
    }
      inputController.text = _commandHistory[historyPointer]; // Handle  key event if needed
    return;
  }
}