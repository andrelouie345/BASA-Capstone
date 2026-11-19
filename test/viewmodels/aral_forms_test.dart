// AralFormsViewModel: ARAL Forms 1, 2 and 4 (Reading) from the device copy
// (ARAL memo Plan B Task 5; spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md
// section 8). Read-only; admin build.
//
// School 1 'ZZ Forms School' (ZZF1), 2026-2027, values_aral actual (default):
//   Section 71 Two (G2, adviser 'Ms. Two'), section 72 Seven (G7, adviser
//   'Mr. Seven' = tutor Cruz's account).
//   Tutors: Cruz, Ana (internal), Santos, Carla (external).
//   Classes:
//     ARAL-R-G2-01  G2 KS1, Cruz, MWF 7:30-8:15, Room 3, pull-out
//                   Garcia, Gina Mendoza (F, 701): BoSY Low Emerging, MoSY Developing
//                   Abad, Hugo (M, 702):          BoSY High Emerging, MoSY Developing
//                   sessions 09-07 60 min, 09-08 45, 09-09 45 (Gina present at the
//                   first, Hugo absent at all), 11-16 30 min (after the Form 4 date)
//     ARAL-R-G7-01  G7 KS3 Basic, no tutor, schedule, room or session type
//                   Perez, Pia (F, 703):  BoSY 3/10, MoSY 1 9/10 (grade level)
//                   Quino, Quin (M, 704): nothing read, basis manual (no basis round)
//     ARAL-R-G7-02  G7 KS3 Basic, Santos, no learners
//   Ramos, Rey (M, 705), G7: BoSY 9/10, exited grade-level ready 2026-09-01, no class.
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_class_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/aral_enrollment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/aral_session_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/user_repository_sqlite.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_forms_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_online_auth.dart';
import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _two = 71, _seven = 72;
const gina = 701, hugo = 702, pia = 703, quin = 704, rey = 705;
const _cruz = '00000000-0000-0000-0000-0000000005c1';
const _santos = '00000000-0000-0000-0000-0000000005c2';
const _asOf = '2026-11-14';

void main() {
  late AppContext ctx;
  late AdminVms adm;
  late int classA, classB, classC;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_forms_').path);
    final s = wireShared(ctx);
    final t = wireTutor(ctx, s);
    adm = await wireAdmin(ctx, s, t);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZF1', 'school_name': 'ZZ Forms School', 'region_id': 13});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-0000000005f1', email: 'forms@test', role: 'coordinator', schoolId: 1);
    for (final (id, name, type) in [(_cruz, 'Cruz, Ana', 'internal'), (_santos, 'Santos, Carla', 'external')]) {
      await db.insert('users', {'id': id, 'email': '$id@zz', 'full_name': name, 'role': 'tutor', 'school_id': 1,
          'is_active': 1, 'tutor_type': type});
    }
    await db.insert('sections', {'id': _two, 'school_id': 1, 'school_year': _year, 'grade_level': '2',
        'section_name': 'Two', 'adviser_name': 'Ms. Two'});
    await db.insert('sections', {'id': _seven, 'school_id': 1, 'school_year': _year, 'grade_level': '7',
        'section_name': 'Seven', 'adviser_name': 'Mr. Seven', 'adviser_user_id': _cruz});
    for (final (id, last, first, middle, sex) in [
      (gina, 'Garcia', 'Gina', 'Mendoza', 'F'),
      (hugo, 'Abad', 'Hugo', null, 'M'),
      (pia, 'Perez', 'Pia', null, 'F'),
      (quin, 'Quino', 'Quin', null, 'M'),
      (rey, 'Ramos', 'Rey', null, 'M'),
    ]) {
      await db.insert('students', {'id': id, 'lrn': '00999999$id', 'last_name': last, 'first_name': first,
          'middle_name': middle, 'school_id': 1, 'sex': sex});
      await db.insert('enrollments',
          {'student_id': id, 'section_id': id <= hugo ? _two : _seven, 'school_year': _year, 'status': 'active'});
    }
    var attempt = 0;
    Future<void> crla(int student, String round, String profile, String at) {
      attempt++;
      return db.insert('crla_assessments', {
        'id': -100 - attempt, 'student_id': student, 'school_id': 1, 'section_id': _two, 'school_year': _year,
        'subject_variant': 'fil', 'language': 'Filipino', 'round': round, 'attempt_no': attempt,
        'assessed_at': at, 'reading_profile': profile,
      });
    }
    await crla(gina, 'bosy', crlaLowEmerging, '2026-08-05');
    await crla(gina, 'mosy', crlaDeveloping, '2026-10-05');
    await crla(hugo, 'bosy', crlaHighEmerging, '2026-08-05');
    await crla(hugo, 'mosy', crlaDeveloping, '2026-10-06');

    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded rounds', 'is_grade_leveled': 1});
    for (var n = 1; n <= 2; n++) {
      final id = 500 + n;
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (var k = 1; k <= 10; k++) {
        await db.insert('phil_iri_questions',
            {'id': id * 100 + k, 'passage_id': id, 'question_no': k, 'prompt': 'Q$k', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    expect(await ctx.authVm.signInOffline(email: 'forms@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    Future<void> read(int student, PhilIriRound round, DateTime at, int passageNo, int correct) async {
      final sess = await vm.startSession(studentId: student, sectionId: _seven, schoolYear: _year, round: round, assessedAt: at);
      final passage = 500 + passageNo;
      final rd = await vm.startReading(
          assessmentId: sess.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var k = 1; k <= 10; k++) {
        await vm.answer(readingId: rd.id!, questionId: passage * 100 + k, chosen: k <= correct ? 'a' : 'b');
      }
      await vm.complete(sess.id!);
    }

    await read(pia, PhilIriRound.bosy, DateTime(2026, 8, 5), 1, 3);
    await read(pia, PhilIriRound.mosy1, DateTime(2026, 10, 5), 2, 9);
    await read(rey, PhilIriRound.bosy, DateTime(2026, 8, 5), 1, 9);

    // The roster as the pull leaves it (the proposal rules are not under test).
    Future<void> roster(int student, int section, String ks, {String? basisRound = 'bosy', bool exited = false}) async {
      await db.insert('aral_enrollments', {
        'id': -student, 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': _year,
        'key_stage': ks, 'track': ks == 'ks1' ? null : 'basic', 'status': 'active',
        'entered_on': '2026-08-10', 'basis_source': 'manual', 'basis_round': basisRound,
      });
      // A new enrollment starts active; the grade-level-ready exit follows (as applyResults writes it).
      if (exited) {
        await db.update('aral_enrollments',
            {'status': 'exited', 'exited_on': '2026-09-01', 'exit_reason': 'grade_level_ready'},
            where: 'id = ?', whereArgs: [-student]);
      }
    }
    await roster(gina, _two, 'ks1');
    await roster(hugo, _two, 'ks1');
    await roster(pia, _seven, 'ks3');
    await roster(quin, _seven, 'ks3', basisRound: null);
    await roster(rey, _seven, 'ks3', exited: true);

    final classes = t.aralClassVm;
    classA = (await classes.createClass(schoolId: 1, schoolYear: _year, className: 'ARAL-R-G2-01', gradeLevel: 2,
            program: AralClassProgram.ks1, tutorId: _cruz, room: 'Room 3', schedule: 'MWF 7:30-8:15',
            sessionType: AralSessionType.pullOut))
        .id!;
    classB = (await classes.createClass(schoolId: 1, schoolYear: _year, className: 'ARAL-R-G7-01', gradeLevel: 7,
            program: AralClassProgram.ks3Basic))
        .id!;
    classC = (await classes.createClass(schoolId: 1, schoolYear: _year, className: 'ARAL-R-G7-02', gradeLevel: 7,
            program: AralClassProgram.ks3Basic, tutorId: _santos))
        .id!;
    for (final (e, c) in [(gina, classA), (hugo, classA), (pia, classB), (quin, classB)]) {
      await classes.place(-e, c);
    }
    final sessions = t.aralSessionVm;
    final held = <int>[];
    for (final (d, m) in [(DateTime(2026, 9, 7), 60), (DateTime(2026, 9, 8), 45), (DateTime(2026, 9, 9), 45),
        (DateTime(2026, 11, 16), 30)]) {
      held.add((await sessions.logSession(classId: classA, heldOn: d, minutes: m, setup: AralSetup.pullOut)).id!);
    }
    await sessions.mark(held[0], -gina, AralMark.present);
    for (final id in held) {
      await sessions.mark(id, -hugo, AralMark.absent);
    }
  });

  tearDownAll(LocalDatabase.close);

  AralFormsViewModel forms() => adm.aralFormsVm;

  group('Form 1', () {
    test('one sheet per class, header fields, blanks for what BASA does not hold', () async {
      final all = await forms().form1(schoolId: 1, schoolYear: _year);
      expect(all.map((f) => f.classCode), ['ARAL-R-G2-01', 'ARAL-R-G7-01', 'ARAL-R-G7-02']);
      final a = all.first;
      expect((a.schoolName, a.schoolCode, a.grade, a.learningArea), ('ZZ Forms School', 'ZZF1', 2, 'Reading'));
      expect((a.tutorName, a.tutorType, a.sessionType, a.schedule, a.venue),
          ('Cruz, Ana', 'Internal', 'Pull-out', 'MWF 7:30-8:15', 'Room 3'));
      expect((a.male, a.female, a.total), (1, 1, 2));
      expect(a.blanks, containsAll(['district', 'workbook issued', 'remarks', 'signatures']));
    });

    test('rows by last name: LRN, Last, First M., home section, adviser, MoSY tool and result', () async {
      final a = (await forms().form1(schoolId: 1, schoolYear: _year, classId: classA)).single;
      expect(a.rows.map((r) => r.name), ['Abad, Hugo', 'Garcia, Gina M.']);
      final g = a.rows[1];
      expect((g.lrn, g.sex, g.homeGrade, g.section, g.adviser), ('00999999$gina', 'F', 2, 'Two', 'Ms. Two'));
      expect((g.mosyTool, g.mosyResult, g.workbookIssued, g.remarks), ('CRLA', crlaDeveloping, '', ''));
    });

    test('a class without tutor, schedule, room, session type: blanks, never null', () async {
      final b = (await forms().form1(schoolId: 1, schoolYear: _year, classId: classB)).single;
      expect((b.tutorName, b.tutorType, b.sessionType, b.schedule, b.venue), ('', '', '', '', ''));
      expect(b.rows.map((r) => r.name), ['Perez, Pia', 'Quino, Quin']);
      expect((b.rows[0].mosyTool, b.rows[0].mosyResult), ('Phil-IRI', 'Grade level'));
      // Quin has no MoSY result of his own: tool and result blank.
      expect((b.rows[1].mosyTool, b.rows[1].mosyResult, b.rows[1].adviser), ('', '', 'Mr. Seven'));
      final c = (await forms().form1(schoolId: 1, schoolYear: _year, classId: classC)).single;
      expect(c.rows, isEmpty);
      expect((c.total, c.tutorType), (0, 'External'));
    });

    test('a class of another school or year is refused', () async {
      expect(() => forms().form1(schoolId: 1, schoolYear: '2025-2026', classId: classA),
          throwsA(isA<ViewModelException>()));
    });
  });

  group('Form 2', () {
    test('one row per class; the shared result or mixed; the advisory class; footer counts', () async {
      final f = await forms().form2(schoolId: 1, schoolYear: _year);
      expect(f.rows.map((r) => r.classCode), ['ARAL-R-G2-01', 'ARAL-R-G7-01', 'ARAL-R-G7-02']);
      final a = f.rows[0];
      expect((a.grade, a.area, a.male, a.female, a.total), (2, 'R', 1, 1, 2));
      expect((a.mosyResult, a.tutorName, a.tutorType, a.advisoryClass), (crlaDeveloping, 'Cruz, Ana', 'I', 'Grade 7 Seven'));
      expect((a.schedule, a.sessionType, a.venue), ('MWF 7:30-8:15', 'Pull-out', 'Room 3'));
      expect((f.rows[1].mosyResult, f.rows[1].tutorName, f.rows[1].tutorType), ('mixed', '', ''));
      expect((f.rows[2].mosyResult, f.rows[2].tutorType, f.rows[2].advisoryClass), ('', 'E', ''));
      expect((f.readingClasses, f.readingLearners, f.internalTutors, f.externalTutors), (3, 4, 1, 1));
      expect(f.blanks, containsAll(['district', 'Mathematics columns', 'signatures']));
    });
  });

  group('Form 4', () {
    test('Part I per grade as of the date', () async {
      final f = await forms().form4(schoolId: 1, schoolYear: _year, asOf: _asOf);
      expect(f.grades.map((g) => g.grade), [for (var g = 1; g <= 10; g++) g]);
      final g2 = f.grades[1], g7 = f.grades[6];
      expect((g2.identified, g2.served, g2.reachedGradeLevel, g2.improved, g2.noImprovement, g2.atMosy),
          (2, 1, 0, 2, 0, 2));
      // Rey: identified, exited grade-level ready; Quin: not identified (no basis
      // round), no MoSY result -> No improvement; Pia: improved; no sessions held.
      expect((g7.identified, g7.served, g7.reachedGradeLevel, g7.improved, g7.noImprovement, g7.atMosy),
          (2, 0, 1, 1, 1, 2));
      for (final g in f.grades.where((g) => g.grade != 2 && g.grade != 7)) {
        expect((g.identified, g.served, g.reachedGradeLevel, g.improved, g.noImprovement, g.atMosy),
            (0, 0, 0, 0, 0, 0), reason: 'grade ${g.grade}');
      }
      expect(f.notes.any((n) => n.contains('Quino, Quin') && n.contains('No improvement')), isTrue, reason: '${f.notes}');
      expect(f.notes.any((n) => n.contains('Garcia') || n.contains('Abad')), isFalse);
    });

    test('Part II: classes, tutors by type, sessions and hours by the date', () async {
      final f = await forms().form4(schoolId: 1, schoolYear: _year, asOf: _asOf);
      expect((f.classes, f.internalTutors, f.externalTutors, f.sessions, f.hours), (3, 1, 1, 3, 2.5));
      final later = await forms().form4(schoolId: 1, schoolYear: _year, asOf: '2026-11-16');
      expect((later.sessions, later.hours), (4, 3.0));
    });

    test('before any MoSY: learners without a MoSY result are under No improvement, and the note says so', () async {
      final f = await forms().form4(schoolId: 1, schoolYear: _year, asOf: '2026-09-15');
      final g2 = f.grades[1];
      expect((g2.improved, g2.noImprovement, g2.atMosy), (0, 2, 2));
      expect(f.notes.any((n) => n.contains('without a MoSY result') && n.contains('No improvement')), isTrue,
          reason: '${f.notes}');
    });

    test('a date that is not a date is refused', () async {
      expect(() => forms().form4(schoolId: 1, schoolYear: _year, asOf: '14/11/2026'),
          throwsA(isA<ViewModelException>()));
    });
  });

  group('.xlsx', () {
    test('form1Xlsx: one sheet per class; form2Xlsx and form4Xlsx open', () async {
      final wb = XlsxWorkbook.decode(await forms().form1Xlsx(schoolId: 1, schoolYear: _year));
      expect(wb.sheetNames, ['ARAL-R-G2-01', 'ARAL-R-G7-01', 'ARAL-R-G7-02']);
      expect(wb.read('ARAL-R-G2-01', 'C19'), 'Abad, Hugo');
      expect(XlsxWorkbook.decode(await forms().form2Xlsx(schoolId: 1, schoolYear: _year)).read('Form 2', 'B8'),
          'ARAL-R-G2-01');
      final f4 = XlsxWorkbook.decode(await forms().form4Xlsx(schoolId: 1, schoolYear: _year, asOf: _asOf));
      expect(f4.read('Form 4', 'B26'), 2.5);
    });

    test('form1Xlsx: a year with no classes is refused in plain words', () async {
      expect(() => forms().form1Xlsx(schoolId: 1, schoolYear: '2027-2028'),
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message',
              'This school has no ARAL classes for 2027-2028 yet.')));
    });
  });

  test('a tutor caller is refused; another school is refused', () async {
    final db = ctx.localDb;
    final asTutor = AralFormsViewModel(
      auth: FakeOnlineAuth(UserRole.tutor, schoolId: 1),
      report: adm.aralReportVm,
      classes: AralClassRepositorySqlite(db),
      roster: AralEnrollmentRepositorySqlite(db),
      sessions: AralSessionRepositorySqlite(db),
      users: UserRepositorySqlite(db),
      sections: SectionRepositorySqlite(db),
      students: StudentRepositorySqlite(db),
      schools: SchoolRepositorySqlite(db),
    );
    final notAllowed = throwsA(isA<ViewModelException>().having((e) => e.message, 'message', startsWith('Not allowed:')));
    expect(() => asTutor.form1(schoolId: 1, schoolYear: _year), notAllowed);
    expect(() => asTutor.form2(schoolId: 1, schoolYear: _year), notAllowed);
    expect(() => asTutor.form4(schoolId: 1, schoolYear: _year, asOf: _asOf), notAllowed);
    expect(() => forms().form2(schoolId: 2, schoolYear: _year), notAllowed);
  });
}
