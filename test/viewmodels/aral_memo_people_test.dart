// ARAL memo, people (plan docs/superpowers/plans/2026-11-18-aral-memo-b-people-forms.md,
// Task 3; spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md
// sections 3, 6, 7): the three new settings; the adviser rule in placement and
// in a class's tutor change; the daily tutor limits on logging and editing a
// session; suggested class names; class session type; setting a section's
// adviser and a tutor's type (online). The device copy is SQLite; the class
// and session work is signed in offline as a coordinator, the online-only
// writes through FakeOnlineAuth.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/user_repository_sqlite.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/services/aral_rule_settings.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_class_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_session_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/viewmodels/section_viewmodel.dart';
import 'package:basa_capstone/viewmodels/user_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_online_auth.dart';
import '../helpers/offline_owner.dart';

const _school = 9801;
const _otherSchool = 9802;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000098c1';
const _adviser = '00000000-0000-0000-0000-0000000098a1'; // internal, adviser of ALUMINUM
const _plain = '00000000-0000-0000-0000-0000000098a2'; // no type
const _external = '00000000-0000-0000-0000-0000000098a3';
const _elsewhere = '00000000-0000-0000-0000-0000000098b1'; // coordinator of another school
const _aluminum = 9811, _boron = 9812;

Matcher _refused(String text) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains(text)));

void main() {
  late Database db;
  late AralViewModel aral;
  late AralClassViewModel classes;
  late AralSessionViewModel sessions;
  var nextStudent = 9801;
  var nextClass = 1;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_memo_people_').path);
    db = ctx.localDb;
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    classes = t.aralClassVm;
    sessions = t.aralSessionVm;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZMP1', 'school_name': 'ZZ Memo People'});
    await db.insert('schools', {'id': _otherSchool, 'school_id': 'ZZMP2', 'school_name': 'ZZ Memo People 2'});
    for (final (id, name, type) in [
      (_adviser, 'Cruz, Ana', 'internal'),
      (_plain, 'Reyes, Ben', null),
      (_external, 'Santos, Carla', 'external'),
    ]) {
      await db.insert('users', {'id': id, 'email': '$id@zz', 'full_name': name, 'role': 'tutor', 'school_id': _school,
          'is_active': 1, 'tutor_type': type});
    }
    await db.insert('users', {'id': _elsewhere, 'email': 'else@zz', 'full_name': 'Elsewhere', 'role': 'coordinator',
        'school_id': _otherSchool, 'is_active': 1});
    await db.insert('sections', {'id': _aluminum, 'school_id': _school, 'school_year': _year, 'grade_level': '7',
        'section_name': 'ALUMINUM', 'adviser_name': 'Ms. Cruz', 'adviser_user_id': _adviser});
    await db.insert('sections', {'id': _boron, 'school_id': _school, 'school_year': _year, 'grade_level': '7',
        'section_name': 'BORON'});
    await seedOfflineOwner(db, userId: _coord, email: 'coord98@zz', role: 'coordinator', schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'coord98@zz', password: 'test-pw'), isNull);
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(Map<String, Object?>? school) async {
    await db.delete('aral_settings');
    if (school != null) await db.insert('aral_settings', {'id': 1, 'school_id': _school, 'settings': jsonEncode(school)});
  }

  Future<AralClass> newClass({String? tutor, String? name}) => classes.createClass(
      schoolId: _school, schoolYear: _year, className: name ?? 'C${nextClass++}', gradeLevel: 7,
      program: AralClassProgram.ks3Basic, tutorId: tutor);

  /// A learner of [section] enrolled in ARAL, waiting for a class (or in [classId]).
  Future<AralEnrollment> learner(int section, {int? classId}) async {
    final id = nextStudent++;
    await db.insert('students', {'id': id, 'lrn': '99999998${id.toString().padLeft(4, '0')}', 'last_name': 'Lopez',
        'first_name': 'L$id', 'school_id': _school});
    await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    final e = await aral.enroll(sectionId: section, schoolYear: _year, studentId: id,
        keyStage: AralKeyStage.ks3, track: AralTrack.basic, classId: classId, enteredOn: DateTime(2026, 9, 1));
    return e;
  }

  Future<AralSession> log(AralClass c, String tutor, DateTime on, {int minutes = 45}) =>
      sessions.logSession(classId: c.id!, heldOn: on, minutes: minutes, setup: AralSetup.pullOut, tutorId: tutor);

  group('settings', () {
    test('the three keys: defaults, values, checks', () {
      final d = AralRuleSettings.defaults;
      expect(d.internalTutorMaxSessionsPerDay, isNull);
      expect(d.externalTutorMaxMinutesPerDay, isNull);
      expect(d.adviserTutorsOwnClass, isTrue);
      final s = AralRuleSettings.fromMap({'internal_tutor_max_sessions_per_day': 2,
          'external_tutor_max_minutes_per_day': 120, 'adviser_tutors_own_class': false});
      expect((s.internalTutorMaxSessionsPerDay, s.externalTutorMaxMinutesPerDay, s.adviserTutorsOwnClass), (2, 120, false));
      expect(AralRuleSettings.keys, containsAll(['internal_tutor_max_sessions_per_day',
          'external_tutor_max_minutes_per_day', 'adviser_tutors_own_class']));
      expect(aralRuleSettingProblem('internal_tutor_max_sessions_per_day', 11), isNotNull);
      expect(aralRuleSettingProblem('internal_tutor_max_sessions_per_day', 10), isNull);
      expect(aralRuleSettingProblem('external_tutor_max_minutes_per_day', 601), isNotNull);
      expect(aralRuleSettingProblem('adviser_tutors_own_class', 'no'), isNotNull);
      expect(aralRuleSettingFromText('adviser_tutors_own_class', 'off'), false);
      expect(s.valueOf('adviser_tutors_own_class'), false);
    });
  });

  group('adviser rule', () {
    test('off by default: the adviser places their own learner', () async {
      await setting(null);
      final c = await newClass(tutor: _adviser);
      final e = await learner(_aluminum);
      await classes.place(e.id!, c.id!);
    });

    test('on: placement refused, naming the learner and section; tutor change refused', () async {
      await setting({'adviser_tutors_own_class': false});
      final mine = await newClass(tutor: _adviser);
      final own = await learner(_aluminum);
      await expectLater(classes.place(own.id!, mine.id!), _refused('Lopez, L'));
      await expectLater(classes.place(own.id!, mine.id!), _refused('ALUMINUM'));
      await expectLater(classes.place(own.id!, mine.id!), _refused('does not tutor their own learners'));
      await classes.place((await learner(_boron)).id!, mine.id!); // another section

      // Enrolling straight into the class: the learner waits, with a warning.
      final waiting = await learner(_aluminum, classId: mine.id);
      expect(waiting.classId, isNull);
      expect(aral.lastWarning, contains('does not tutor their own learners'));

      // A class with one of the adviser's learners can't take them as tutor.
      final other = await newClass(tutor: _plain);
      await classes.place(own.id!, other.id!);
      await expectLater(classes.editClass(other.copyWith(tutorId: () => _adviser)), _refused('ALUMINUM'));
      await classes.editClass(other.copyWith(room: () => 'Library')); // other edits still save

      // A turned-off adviser still advises the section.
      await db.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [_adviser]);
      await expectLater(classes.place((await learner(_aluminum)).id!, mine.id!), _refused('does not tutor'));
      await db.update('users', {'is_active': 1}, where: 'id = ?', whereArgs: [_adviser]);
      await setting(null);
    });
  });

  group('daily tutor limits', () {
    test('internal: sessions a day; edit onto a full day', () async {
      await setting({'internal_tutor_max_sessions_per_day': 2});
      final a = await newClass(tutor: _adviser), b = await newClass(tutor: _adviser), c = await newClass(tutor: _adviser);
      await log(a, _adviser, DateTime(2026, 11, 16));
      await log(b, _adviser, DateTime(2026, 11, 16));
      await expectLater(log(c, _adviser, DateTime(2026, 11, 16)), _refused('at most 2 ARAL sessions a day'));
      await expectLater(log(c, _adviser, DateTime(2026, 11, 16)), _refused('already has 2 on 2026-11-16'));
      final next = await log(c, _adviser, DateTime(2026, 11, 17));
      await expectLater(sessions.editSession(next.id!, heldOn: DateTime(2026, 11, 16)), _refused('at most 2 ARAL sessions'));
      await sessions.editSession(next.id!, remarks: () => 'fine');
      await setting(null);
    });

    test('external: minutes a day', () async {
      await setting({'external_tutor_max_minutes_per_day': 120});
      final a = await newClass(tutor: _external), b = await newClass(tutor: _external), c = await newClass(tutor: _external);
      final first = await log(a, _external, DateTime(2026, 11, 18), minutes: 60);
      await log(b, _external, DateTime(2026, 11, 18), minutes: 60);
      await expectLater(log(c, _external, DateTime(2026, 11, 18), minutes: 1), _refused('at most 120 minutes of ARAL sessions a day'));
      await expectLater(sessions.editSession(first.id!, minutes: 61), _refused('at most 120 minutes of ARAL sessions a day'));
      await sessions.editSession(first.id!, minutes: 50);
      await setting(null);
    });

    test('no type: no limit; a type set later does not re-check saved days', () async {
      await setting({'internal_tutor_max_sessions_per_day': 2, 'external_tutor_max_minutes_per_day': 120});
      final a = await newClass(tutor: _plain), b = await newClass(tutor: _plain), c = await newClass(tutor: _plain);
      final s = await log(a, _plain, DateTime(2026, 11, 19), minutes: 120);
      await log(b, _plain, DateTime(2026, 11, 19), minutes: 120);
      await log(c, _plain, DateTime(2026, 11, 19), minutes: 120);
      await db.update('users', {'tutor_type': 'internal'}, where: 'id = ?', whereArgs: [_plain]);
      await sessions.editSession(s.id!, remarks: () => 'kept');
      final d = await newClass(tutor: _plain);
      await expectLater(log(d, _plain, DateTime(2026, 11, 19)), _refused('at most 2 ARAL sessions a day'));
      await db.update('users', {'tutor_type': null}, where: 'id = ?', whereArgs: [_plain]);
      await setting(null);
    });

    test("a server refusal of the external limit keeps its own words", () {
      expect(aralSessionDbRefusal('PostgrestException(message: an external tutor holds at most 90 minutes of '
              'ARAL sessions a day at this school (100 on 2026-11-18))'),
          'An external tutor holds at most 90 minutes of ARAL sessions a day at this school.');
      expect(aralSessionDbRefusal('an internal tutor holds at most 3 ARAL sessions a day at this school (4 on 2026-11-18)'),
          'An internal tutor holds at most 3 ARAL sessions a day at this school.');
      expect(aralSessionDbRefusal('something else'), isNull);
    });
  });

  group('classes', () {
    test('suggested names: highest number + 1, ignoring case', () async {
      expect(await classes.suggestClassName(schoolId: _school, schoolYear: _year, grade: 4), 'ARAL-R-G4-01');
      await newClass(name: 'aral-r-g4-01');
      expect(await classes.suggestClassName(schoolId: _school, schoolYear: _year, grade: 4), 'ARAL-R-G4-02');
      await newClass(name: 'ARAL-R-G4-03');
      expect(await classes.suggestClassName(schoolId: _school, schoolYear: _year, grade: 4), 'ARAL-R-G4-04');
      expect(await classes.suggestClassName(schoolId: _school, schoolYear: _year, grade: 10), 'ARAL-R-G10-01');
      expect(await classes.suggestClassName(schoolId: _school, schoolYear: '2027-2028', grade: 4), 'ARAL-R-G4-01');
    });

    test('session type saved and shown', () async {
      final c = await classes.createClass(schoolId: _school, schoolYear: _year, className: 'Typed', gradeLevel: 7,
          sessionType: AralSessionType.pullOut);
      expect((await classes.getClass(c.id!)).sessionType, AralSessionType.pullOut);
      final e = await classes.editClass(c.copyWith(sessionType: () => AralSessionType.beforeAfter));
      expect(e.sessionType, AralSessionType.beforeAfter);
      expect((await classes.editClass(e.copyWith(sessionType: () => null))).sessionType, isNull);
    });
  });

  group('online writes', () {
    SectionViewModel sectionVm() => SectionViewModel(
        auth: FakeOnlineAuth(UserRole.coordinator, id: _coord, schoolId: _school),
        repoFactory: (_) => SectionRepositorySqlite(db),
        userRepoFactory: (_) => UserRepositorySqlite(db),
        local: SectionRepositorySqlite(db));

    test("a section's adviser: name only, linked, kept, cleared, filled from the account", () async {
      final vm = sectionVm();
      var s = await vm.setAdviser(_boron, name: 'Mr. Dela Cruz');
      expect((s.adviserName, s.adviserUserId), ('Mr. Dela Cruz', null)); // no account needed
      s = await vm.setAdviser(_boron, name: 'Mr. Dela Cruz', userId: _plain);
      expect(s.adviserUserId, _plain);
      s = await vm.setAdviser(_boron, name: 'Mr. Dela Cruz Jr.'); // userId left out: link kept
      expect((s.adviserName, s.adviserUserId), ('Mr. Dela Cruz Jr.', _plain));
      s = await vm.setAdviser(_boron, name: null, userId: _plain); // no name: the account's
      expect(s.adviserName, 'Reyes, Ben');
      s = await vm.setAdviser(_boron, name: 'Mr. Dela Cruz', clearUser: true);
      expect((s.adviserName, s.adviserUserId), ('Mr. Dela Cruz', null));
      s = await vm.setAdviser(_boron, name: null);
      expect((s.adviserName, s.adviserUserId), (null, null));
      // Stored on the device too.
      final local = (await SectionRepositorySqlite(db).getById(_boron))!;
      expect((local.adviserName, local.adviserUserId), (null, null));
    });

    test('a tutor is refused before any lookup; a missing section is named without its id', () async {
      final asTutor = SectionViewModel(
          auth: FakeOnlineAuth(UserRole.tutor, id: _plain, schoolId: _school),
          repoFactory: (_) => SectionRepositorySqlite(db),
          userRepoFactory: (_) => UserRepositorySqlite(db),
          local: SectionRepositorySqlite(db));
      // A section the tutor's device doesn't hold (command pass r56 L119).
      await expectLater(asTutor.setAdviser(987654, name: 'X'), _refused('Not allowed: admin or coordinator only.'));
      await expectLater(sectionVm().setAdviser(987654, name: 'X'),
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'That section was not found.')));
    });

    test('an adviser account of another school is refused', () async {
      await expectLater(sectionVm().setAdviser(_boron, name: 'X', userId: _elsewhere), _refused("section's school"));
      await expectLater(sectionVm().setAdviser(_boron, name: 'X', userId: 'no-such-user'), _refused("section's school"));
    });

    test("a tutor's type: set, cleared; never another school's user or one's own", () async {
      final vm = UserViewModel(auth: FakeOnlineAuth(UserRole.coordinator, id: _coord, schoolId: _school),
          repoFactory: (_) => UserRepositorySqlite(db), local: UserRepositorySqlite(db));
      expect((await vm.setTutorType(_plain, TutorType.external)).tutorType, TutorType.external);
      expect((await UserRepositorySqlite(db).getById(_plain))!.tutorType, TutorType.external);
      expect((await vm.setTutorType(_plain, null)).tutorType, isNull);
      await expectLater(vm.setTutorType(_elsewhere, TutorType.internal), _refused('Not allowed'));
      await expectLater(vm.setTutorType(_coord, TutorType.internal), _refused('your own'));
    });
  });
}
