// lib/core/models/text_state.dart
class TextState {
  final String value;
  const TextState(this.value);

  TextState copyWith(String newValue) => TextState(newValue);
}