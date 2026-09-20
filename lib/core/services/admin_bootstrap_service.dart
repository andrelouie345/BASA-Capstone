// lib/core/services/admin_bootstrap_service.dart
import 'package:supabase/supabase.dart' hide User;

class AdminBootstrapService {
  final SupabaseClient client;
  AdminBootstrapService(this.client);

  Future<void> bootstrapFirstAdmin({required String email, required String fullName}) async {
    final response = await client.functions.invoke('bootstrap-admin', body: {
      'email': email,
      'full_name': fullName,
    });

    if (response.status != 200) {
      throw Exception('bootstrap-admin failed (${response.status}): ${response.data}');
    }
  }
}