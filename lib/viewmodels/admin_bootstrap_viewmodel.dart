// lib/viewmodels/admin_bootstrap_viewmodel.dart
import 'package:supabase/supabase.dart' show FunctionException;

import '../core/console/logger.dart';
import '../core/services/admin_bootstrap_service.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

class AdminBootstrapViewModel {
  final ScopedLogger _log;
  final AdminBootstrapService _service;

  AdminBootstrapViewModel({required AdminBootstrapService service, Logger? logger})
      : _service = service,
        _log = ScopedLogger(logger, 'AdminBootstrapViewModel');

  Future<String?> bootstrap(String email, String fullName) async {
    _log('bootstrap(email: "$email", fullName: "$fullName")');
    try {
      return await _service.bootstrapFirstAdmin(email: email, fullName: fullName);
    } on FunctionException catch (e) {
      throw ViewModelException(edgeFunctionErrorMessage(e));
    }
  }
}