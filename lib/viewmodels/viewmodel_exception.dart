// lib/viewmodels/viewmodel_exception.dart

/// A refusal or failure a ViewModel wants shown to the user as-is
/// ("Not signed in", "Forbidden: ...", "Section still has enrollments").
/// toString() is the bare message, so UI and console can print it directly.
class ViewModelException implements Exception {
  final String message;
  const ViewModelException(this.message);

  @override
  String toString() => message;
}
