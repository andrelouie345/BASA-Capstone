// lib/viewmodels/text_viewmodel.dart
import '../core/models/text_state.dart';
import '../core/console/logger.dart';

class TextViewModel {
  final ScopedLogger _log;
  TextState _state = const TextState('');

  TextViewModel({Logger? logger}) : _log = ScopedLogger(logger, 'TextViewModel');

  String get value => _state.value;

  void setText(String newValue) {
    _log('setText(newValue: "$newValue")');
    _state = _state.copyWith(newValue);
  }

  void clear() {
    _log('clear()');
    _state = _state.copyWith('');
  }

  void append(String extra) {
    _log('append(extra: "$extra")');
    _state = _state.copyWith(_state.value + extra);
  }
}