// lib/core/viewmodels/viewmodel_registry.dart
class ViewModelRegistry {
  final Map<String, Object> _viewModels = {};

  void register(String name, Object viewModel) {
    _viewModels[name] = viewModel;
  }

  List<String> get names => _viewModels.keys.toList()..sort();
}