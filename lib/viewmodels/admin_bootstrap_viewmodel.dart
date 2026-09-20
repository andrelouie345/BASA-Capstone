// lib/viewmodels/admin_bootstrap_viewmodel.dart
import '../core/console/logger.dart';
import '../core/services/admin_bootstrap_service.dart';

class AdminBootstrapViewModel {
  final ScopedLogger _log;
  final AdminBootstrapService _service;

  AdminBootstrapViewModel({required AdminBootstrapService service, Logger? logger})
      : _service = service,
        _log = ScopedLogger(logger, 'AdminBootstrapViewModel');

  Future<void> bootstrap(String email, String fullName) async {
    _log('bootstrap(email: "$email", fullName: "$fullName")');
    await _service.bootstrapFirstAdmin(email: email, fullName: fullName);
  }
}