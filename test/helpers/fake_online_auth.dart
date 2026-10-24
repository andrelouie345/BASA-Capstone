// Test helper: an AuthViewModel stand-in that is "signed in online" as
// [user] without a server. Its client points nowhere and is never called:
// the ViewModel under test gets fake repositories from its factory
// parameters. Only the members ViewModels use are implemented.
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/viewmodels/auth_viewmodel.dart';
import 'package:supabase/supabase.dart' hide User;

class FakeOnlineAuth implements AuthViewModel {
  @override
  User? currentUser;
  @override
  bool mustChangePassword = false;
  final SupabaseClient _client = SupabaseClient('http://127.0.0.1:9', 'test-anon-key');

  FakeOnlineAuth(UserRole role, {String id = '00000000-0000-0000-0000-00000000fa01', int? schoolId = 1})
      : currentUser = User(id: id, email: '${role.name}@test', fullName: 'Test ${role.name}', role: role,
            createdAt: DateTime.utc(2026), schoolId: schoolId);

  /// Signed out: every guard refuses.
  FakeOnlineAuth.signedOut() : currentUser = null;

  @override
  SupabaseClient? get client => currentUser == null ? null : _client;
  @override
  bool get isSignedIn => currentUser != null;
  @override
  bool get isOffline => false;
  @override
  String? requireActiveSession() => currentUser == null ? notSignedInMessage : null;
  @override
  String? requireOnlineSession({bool allowPendingPasswordChange = false}) => requireActiveSession();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
