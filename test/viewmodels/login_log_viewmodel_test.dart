// The login log checks the sign-in and the role itself (screen inventory
// ADMIN-G1): before, only the console command did.
import 'package:basa_capstone/core/models/login_log.dart';
import 'package:basa_capstone/core/models/login_method.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/login_log_repository.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/viewmodels/login_log_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_online_auth.dart';

class _Logs implements LoginLogRepository {
  final List<LoginLog> rows;
  _Logs(this.rows);
  @override
  Future<void> log(LoginLog attempt) async => rows.add(attempt);
  @override
  Future<List<LoginLog>> getRecent({int limit = 50}) async => rows.take(limit).toList();
  @override
  Future<List<LoginLog>> getForUser(String userId) async => rows.where((l) => l.userId == userId).toList();
}

LoginLog _at(String email, int minute) =>
    LoginLog(emailAttempted: email, success: true, method: LoginMethod.online, timestamp: DateTime.utc(2026, 10, 24, 8, minute));

Matcher _refused(String message) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  LoginLogViewModel vmFor(FakeOnlineAuth auth, {List<LoginLog>? local, List<LoginLog>? cloud}) =>
      LoginLogViewModel(repo: _Logs(local ?? []), auth: auth, cloudFor: (_) => _Logs(cloud ?? []));

  test('loadRecent refuses a tutor', () async {
    await expectLater(vmFor(FakeOnlineAuth(UserRole.tutor)).loadRecent(), _refused('Forbidden: admin or coordinator only.'));
  });

  test('record refuses signed out', () async {
    await expectLater(vmFor(FakeOnlineAuth.signedOut()).record(_at('a@test', 1)), _refused(notSignedInMessage));
  });

  test('loadForUser refuses signed out', () async {
    await expectLater(vmFor(FakeOnlineAuth.signedOut()).loadForUser('x'), _refused(notSignedInMessage));
  });

  test('loadRecent merges local and cloud', () async {
    final both = _at('both@test', 3);
    final vm = vmFor(FakeOnlineAuth(UserRole.coordinator), local: [_at('local@test', 1), both], cloud: [both, _at('cloud@test', 2)]);

    await vm.loadRecent();

    expect([for (final s in vm.items) '${s.log.emailAttempted} ${s.sourceLabel}'],
        ['both@test local+cloud', 'cloud@test cloud', 'local@test local']);
    expect(vm.cloudError, isNull);
  });
}
