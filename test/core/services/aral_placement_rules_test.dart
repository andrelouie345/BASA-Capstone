// ARAL classes: programs, the home grade and the placement check (the cloud's
// aral_check_class_placement, 20261024010000, checks school, program and the
// cap; the grade is the coordinator's confirmation, checked only here).
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/services/aral_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rose = AralClass(
    id: 7,
    schoolId: 1,
    schoolYear: '2026-2027',
    className: '7-Rose',
    gradeLevel: 7,
    program: AralClassProgram.ks3Basic,
  );
  const mixed = AralClass(id: 8, schoolId: 1, schoolYear: '2026-2027', className: '7-Mixed', gradeLevel: 7);

  AralPlacementProblem? check({
    AralClass target = rose,
    int schoolId = 1,
    String schoolYear = '2026-2027',
    AralClassProgram program = AralClassProgram.ks3Basic,
    int grade = 7,
    int others = 0,
    bool otherGradeOk = false,
  }) =>
      aralPlacementProblem(
          target: target,
          schoolId: schoolId,
          schoolYear: schoolYear,
          program: program,
          grade: grade,
          activeOthersInClass: others,
          otherGradeOk: otherGradeOk);

  test('a program from key stage and track', () {
    expect(AralClassProgram.of(AralKeyStage.ks2, AralTrack.basic), AralClassProgram.ks2Basic);
    expect(AralClassProgram.of(AralKeyStage.ks3, AralTrack.plus), AralClassProgram.ks3Plus);
    expect(AralClassProgram.of(AralKeyStage.ks1, null), AralClassProgram.ks1);
    expect(AralClassProgram.of(AralKeyStage.foundational, null), AralClassProgram.foundational);
    expect(AralClassProgram.fromString('ks2_plus'), AralClassProgram.ks2Plus);
    expect(AralClassProgram.ks2Plus.value, 'ks2_plus');
    expect(AralClassProgram.ks2Plus.label, 'KS2 Plus');
    expect(() => AralClassProgram.fromString('ks2'), throwsArgumentError);
  });

  test('group label', () {
    expect(rose.groupLabel, 'Grade 7, KS3 Basic');
    expect(mixed.groupLabel, 'Grade 7, mixed programs');
    expect(mixed.isMixed, isTrue);
    expect(rose.isMixed, isFalse);
  });

  test('a class takes 15 active learners', () {
    expect(check(others: 14), isNull);
    expect(check(others: 15), AralPlacementProblem.full);
    expect(check(target: mixed, others: 15), AralPlacementProblem.full);
  });

  test('program and school are checked; a mixed class takes any program', () {
    expect(check(program: AralClassProgram.ks2Plus), AralPlacementProblem.programMismatch);
    expect(check(schoolId: 2), AralPlacementProblem.otherSchoolOrYear);
    expect(check(schoolYear: '2027-2028'), AralPlacementProblem.otherSchoolOrYear);
    for (final p in AralClassProgram.values) {
      expect(check(target: mixed, program: p), isNull, reason: p.value);
    }
  });

  test('another grade only with the coordinator\'s confirmation', () {
    expect(check(grade: 9), AralPlacementProblem.otherGrade);
    expect(check(grade: 9, otherGradeOk: true), isNull);
    expect(check(target: mixed, grade: 5, program: AralClassProgram.ks1), AralPlacementProblem.otherGrade);
    expect(check(target: mixed, grade: 5, program: AralClassProgram.ks1, otherGradeOk: true), isNull);
    // Confirming the grade doesn't lift the cap.
    expect(check(grade: 9, otherGradeOk: true, others: 15), AralPlacementProblem.full);
  });

  test('the first problem wins: school, program, grade, cap', () {
    expect(check(schoolId: 2, program: AralClassProgram.ks1, grade: 2, others: 15), AralPlacementProblem.otherSchoolOrYear);
    expect(check(program: AralClassProgram.ks1, grade: 2, others: 15), AralPlacementProblem.programMismatch);
    expect(check(grade: 5, others: 15), AralPlacementProblem.otherGrade);
  });

  test('messages', () {
    String msg(AralPlacementProblem p, {int grade = 7, AralClassProgram program = AralClassProgram.ks3Basic}) =>
        aralPlacementMessage(p, learner: 'DELA CRUZ, JUAN', target: rose, grade: grade, program: program);
    expect(msg(AralPlacementProblem.full), 'Class "7-Rose" already has 15 active ARAL learners.');
    expect(msg(AralPlacementProblem.programMismatch, program: AralClassProgram.ks2Plus),
        'DELA CRUZ, JUAN is in KS2 Plus; class "7-Rose" is KS3 Basic.');
    expect(msg(AralPlacementProblem.otherGrade, grade: 9), 'DELA CRUZ, JUAN is in Grade 9; class "7-Rose" is for Grade 7.');
    expect(msg(AralPlacementProblem.otherSchoolOrYear), 'Class "7-Rose" belongs to another school or school year.');
  });

  test('a class row round-trips; null program = mixed', () {
    final c = AralClass.fromMap({
      'id': -3, 'school_id': 1, 'school_year': '2026-2027', 'class_name': '7-Rose', 'program': 'ks3_basic',
      'grade_level': 7, 'tutor_id': 'u1', 'room': 'Rm 4', 'schedule': null, 'notes': null,
      'created_by': 'c1', 'created_at': '2026-10-24T00:00:00Z', 'updated_at': '2026-10-24T00:00:00Z',
    });
    expect(c.program, AralClassProgram.ks3Basic);
    expect(c.gradeLevel, 7);
    expect(c.toMap()['program'], 'ks3_basic');
    expect(c.toMap()['grade_level'], 7);
    expect(c.toMap().containsKey('grade_band'), isFalse);
    expect(c.copyWith(tutorId: () => null).tutorId, isNull);
    expect(c.copyWith(room: () => 'Rm 5').room, 'Rm 5');
    expect(c.copyWith().tutorId, 'u1');
    expect(c.copyWith(program: () => null).program, isNull);
    expect(c.copyWith(gradeLevel: 8).gradeLevel, 8);
    final m = AralClass.fromMap({...c.toMap(), 'program': null});
    expect(m.program, isNull);
    expect(m.toMap()['program'], isNull);
  });
}
