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
import 'package:basa_capstone/core/services/aral_rule_settings.dart';
import 'package:basa_capstone/viewmodels/aral_checkin_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
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

  group('ARAL memo settings (spec 2026-11-18)', () {
    late _MemSettings cloud;
    late _MemSettings local;
    AralCheckinViewModel vmAs(UserRole role, {int? schoolId = 1}) => AralCheckinViewModel(
          auth: FakeOnlineAuth(role, schoolId: schoolId),
          checkins: _NoCheckins(),
          roster: _NoRoster(),
          localSettings: local,
          cloudSettings: (_) => cloud,
          sections: _NoSections(),
          students: _NoStudents(),
        );

    setUp(() {
      cloud = _MemSettings();
      local = _MemSettings();
    });

    test('setRuleSetting writes, mirrors and removes', () async {
      final coord = vmAs(UserRole.coordinator);
      expect((await coord.localRuleSettings(1)).classMaxLearners, 15);
      await coord.setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, 10);
      expect((await coord.localRuleSettings(1)).classMaxLearners, 10);
      final layers = await coord.ruleSettingLayers(AralRuleSettings.classMaxLearnersKey, 1);
      expect(layers.school, 10);
      expect(layers.region, isNull);
      expect(layers.effective, 10);
      expect(layers.defaults, 15);
      await coord.setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, null);
      expect((await coord.localRuleSettings(1)).classMaxLearners, 15);
    });

    test('a list value is stored as given', () async {
      final coord = vmAs(UserRole.coordinator);
      await coord.setRuleSetting(1, AralRuleSettings.checkinAfterSessionsKey, [12, 24]);
      expect((await coord.localRuleSettings(1)).checkinAfterSessions, [12, 24]);
    });

    test('bad values and a minimum above the maximum are refused', () async {
      final coord = vmAs(UserRole.coordinator);
      await expectLater(coord.setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, 0),
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains('1-50'))));
      await coord.setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, 10);
      await expectLater(coord.setRuleSetting(1, AralRuleSettings.classMinLearnersKey, 12),
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains('maximum'))));
      await coord.setRuleSetting(1, AralRuleSettings.classMinLearnersKey, 5);
      await expectLater(coord.setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, 4),
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains('minimum'))));
    });

    test('a tutor, or another school, is refused', () async {
      await expectLater(vmAs(UserRole.tutor).setRuleSetting(1, AralRuleSettings.classMaxLearnersKey, 10),
          throwsA(isA<ViewModelException>()));
      await expectLater(vmAs(UserRole.coordinator).setRuleSetting(2, AralRuleSettings.classMaxLearnersKey, 10),
          throwsA(isA<ViewModelException>()));
      await expectLater(vmAs(UserRole.coordinator).setRuleSetting(null, AralRuleSettings.classMaxLearnersKey, 10),
          throwsA(isA<ViewModelException>()));
    });

    test('the superadmin sets the region row; the school row wins', () async {
      final sa = vmAs(UserRole.admin, schoolId: null);
      await sa.setRuleSetting(null, AralRuleSettings.sessionsWeekdaysOnlyKey, true);
      expect((await vmAs(UserRole.coordinator).localRuleSettings(1)).sessionsWeekdaysOnly, isTrue);
      await vmAs(UserRole.coordinator).setRuleSetting(1, AralRuleSettings.sessionsWeekdaysOnlyKey, false);
      expect((await vmAs(UserRole.coordinator).localRuleSettings(1)).sessionsWeekdaysOnly, isFalse);
    });
  });
}

/// The settings rows in memory (region row = school id null).
class _MemSettings implements AralSettingRepository {
  final rows = <int?, AralSetting>{};
  var _next = 1;

  @override
  Future<AralSetting?> getRegion() async => rows[null];
  @override
  Future<AralSetting?> getForSchool(int schoolId) async => rows[schoolId];
  @override
  Future<AralSetting> save(int? schoolId, Map<String, Object?> settings) async =>
      rows[schoolId] = AralSetting(id: rows[schoolId]?.id ?? _next++, schoolId: schoolId, settings: settings);
  @override
  Future<AralSetting> upsertWithId(AralSetting setting) async => rows[setting.schoolId] = setting;
  @override
  Future<void> deleteForSchool(int schoolId) async => rows.remove(schoolId);
  @override
  Future<void> removeMirroredForSchool(int schoolId) async => rows.remove(schoolId);
}
