// The ARAL settings layers carry their default, so a screen shows it
// without naming the rule constants (spec
// docs/superpowers/specs/2026-10-24-vm-completeness-design.md, ARAL-G4).
import 'package:basa_capstone/core/models/aral_setting.dart';
import 'package:basa_capstone/core/models/aral_types.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/aral_checkin_repository.dart';
import 'package:basa_capstone/core/repositories/aral_enrollment_repository.dart';
import 'package:basa_capstone/core/repositories/aral_setting_repository.dart';
import 'package:basa_capstone/core/repositories/section_repository.dart';
import 'package:basa_capstone/core/repositories/student_repository.dart';
import 'package:basa_capstone/viewmodels/aral_checkin_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_online_auth.dart';

/// Nothing stored in the cloud.
class _NoSettings implements AralSettingRepository {
  @override
  Future<AralSetting?> getRegion() async => null;
  @override
  Future<AralSetting?> getForSchool(int schoolId) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCheckins implements AralCheckinRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoRoster implements AralEnrollmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSections implements SectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStudents implements StudentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final vm = AralCheckinViewModel(
    auth: FakeOnlineAuth(UserRole.coordinator),
    checkins: _NoCheckins(),
    roster: _NoRoster(),
    localSettings: _NoSettings(),
    cloudSettings: (_) => _NoSettings(),
    sections: _NoSections(),
    students: _NoStudents(),
  );

  test('cut-off layers carry the default', () async {
    final l = await vm.settingLayers(1);
    expect(l.defaults.passPct, AralCheckinSettings.defaults.passPct);
    expect(l.defaults.passPct, 75);
  });

  test('SHARP layers default to off', () async {
    final l = await vm.foundationalProgramLayers(1);
    expect(l.defaults, isFalse);
    expect(l.effective, isFalse);
  });

  test('extended KS1 layers default to off', () async {
    final l = await vm.ks1ExtendedLayers(1);
    expect(l.defaults, isFalse);
  });

  test('idle session days layers carry the default', () async {
    final l = await vm.idleSessionDaysLayers(1);
    expect(l.defaults, AralSessionSettings.defaults.idleSessionDays);
    expect(l.effective, l.defaults);
  });
}
