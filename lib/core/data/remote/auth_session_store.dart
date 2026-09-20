// lib/core/data/remote/auth_session_store.dart
import 'package:supabase/supabase.dart' hide User;

/// STOPGAP ONLY — holds one signed-in client for the console session.
/// No persistence across restarts, no token refresh handling, no
/// must_change_password enforcement, no multi-session support.
/// This exists purely to unblock testing auth-gated Edge Functions
/// (like create-user) before the real login module is built.
class AuthSessionStore {
  SupabaseClient? client;
  String? signedInEmail;
}