// A change saved online but not copied onto this device sets a warning a
// screen shows as is, so it must not carry the exception's text (spec
// docs/superpowers/specs/2026-10-24-vm-completeness-design.md, class E).
import 'package:basa_capstone/core/models/crla_threshold_setting.dart';
import 'package:basa_capstone/core/models/tutor_section_assignment.dart';
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/crla_assessment_repository.dart';
import 'package:basa_capstone/core/repositories/crla_part1_english_repository.dart';
import 'package:basa_capstone/core/repositories/crla_part1_standard_repository.dart';
import 'package:basa_capstone/core/repositories/crla_threshold_repository.dart';
import 'package:basa_capstone/core/repositories/tutor_section_assignment_repository.dart';
import 'package:basa_capstone/core/repositories/user_repository.dart';
import 'package:basa_capstone/viewmodels/crla_threshold_viewmodel.dart';
import 'package:basa_capstone/viewmodels/tutor_section_assignment_viewmodel.dart';
import 'package:basa_capstone/viewmodels/user_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_online_auth.dart';

class _Users implements UserRepository {
  final bool failing;
  _Users({this.failing = false});
  @override
  Future<void> setActive(String id, bool isActive) async {
    if (failing) throw Exception('locked db');
  }

  @override
  Future<List<User>> getAll() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Assignments implements TutorSectionAssignmentRepository {
  final bool failing;
  _Assignments({this.failing = false});
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> removeMirrored(int id) async {
    if (failing) throw Exception('locked db');
  }

  @override
  Future<List<TutorSectionAssignment>> getByTutor(String tutorId) async => [];
  @override
  Future<List<TutorSectionAssignment>> getBySection(int sectionId) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CrlaThresholds implements CrlaThresholdRepository {
  final bool failing;
  _CrlaThresholds({this.failing = false});
  @override
  Future<CrlaThresholdSetting?> getForSchool(int schoolId) async => CrlaThresholdSetting(schoolId: schoolId, settings: {});
  @override
  Future<void> deleteForSchool(int schoolId) async {}
  @override
  Future<void> removeMirroredForSchool(int schoolId) async {
    if (failing) throw Exception('locked db');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAssessments implements CrlaAssessmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPart1Standard implements CrlaPart1StandardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPart1English implements CrlaPart1EnglishRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('UserViewModel mirror warning has no exception text', () async {
    final vm = UserViewModel(
        auth: FakeOnlineAuth(UserRole.admin), repoFactory: (_) => _Users(), local: _Users(failing: true));

    await vm.setActive('00000000-0000-0000-0000-00000000aaaa', false);

    expect(vm.lastMirrorWarning, 'Saved online, but not copied onto this device; run pull-cloud.');
  });

  test('TutorSectionAssignmentViewModel mirror warning has no exception text', () async {
    final vm = TutorSectionAssignmentViewModel(
        auth: FakeOnlineAuth(UserRole.coordinator),
        repoFactory: (_) => _Assignments(),
        local: _Assignments(failing: true));

    await vm.unassign(1);

    expect(vm.lastMirrorWarning, 'Saved online, but not copied onto this device; run pull-cloud.');
  });

  test('CrlaThresholdViewModel mirror warning has no exception text', () async {
    final vm = CrlaThresholdViewModel(
      auth: FakeOnlineAuth(UserRole.admin, schoolId: null),
      cloudFactory: (_) => CrlaThresholdCloudRepos(
          thresholds: _CrlaThresholds(),
          assessments: _NoAssessments(),
          part1Standard: _NoPart1Standard(),
          part1English: _NoPart1English()),
      localThresholds: _CrlaThresholds(failing: true),
      localAssessments: _NoAssessments(),
      localPart1Standard: _NoPart1Standard(),
      localPart1English: _NoPart1English(),
    );

    await vm.resetSchoolThresholds(1);

    expect(vm.lastMirrorWarning, 'CRLA thresholds saved online, but the local copy was not updated. Run pull-cloud.');
  });
}
