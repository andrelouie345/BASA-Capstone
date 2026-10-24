// lib/viewmodels/admin_bootstrap_viewmodel.dart
import 'package:supabase/supabase.dart' show FunctionException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/data/remote/supabase_config.dart';
import '../core/services/admin_bootstrap_service.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

/// Creates the first admin of a new cloud or LAN server (works once per
/// server, nobody signed in). Picks the server from the saved settings.
class AdminBootstrapViewModel {
  final ScopedLogger _log;
  final SupabaseConfigStore _config;
  final AdminBootstrapService Function(SupabaseClient client) _serviceFor;

  AdminBootstrapViewModel({
    required SupabaseConfigStore config,
    required AdminBootstrapService Function(SupabaseClient client) serviceFor,
    Logger? logger,
  })  : _config = config,
        _serviceFor = serviceFor,
        _log = ScopedLogger(logger, 'AdminBootstrapViewModel');

  /// [target] is `cloud` or `lan`. Returns the temporary password (shown once),
  /// or null when the server function returned none.
  Future<String?> bootstrap(String target, String email, String fullName) async {
    final profile = switch (target) {
      'cloud' => _config.cloud,
      'lan' => _config.lan,
      _ => null,
    };
    if (profile == null) throw const ViewModelException('Usage: bootstrap-admin <cloud|lan> <email> <full name...>');
    if (profile.url.isEmpty) throw ViewModelException('$target.url not set. Use config-set-$target-url first.');
    _log('bootstrap(target: $target, email: "$email", fullName: "$fullName")');
    final service = _serviceFor(SupabaseClient(profile.url, profile.anonKey));
    try {
      return await service.bootstrapFirstAdmin(email: email, fullName: fullName);
    } on FunctionException catch (e) {
      throw ViewModelException(edgeFunctionErrorMessage(e));
    }
  }
}
