// ARAL classes: programs, grade bands and the placement check (same rules as
// the cloud's aral_check_class_placement, 20261023040000).
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
    program: AralClassProgram.ks3Basic,
    gradeBand: AralGradeBand.g7to10,
  );

  AralPlacementProblem? check({
    AralClass target = rose,
    int schoolId = 1,
    String schoolYear = '2026-2027',
    AralClassProgram program = AralClassProgram.ks3Basic,
    int grade = 7,
    int others = 0,
  }) =>
      aralPlacementProblem(
          target: target,
          schoolId: schoolId,
          schoolYear: schoolYear,
          program: program,
          grade: grade,
          activeOthersInClass: others);

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

  test('grade bands', () {
    expect(AralGradeBand.ofGrade(6), AralGradeBand.g4to6);
    expect(AralGradeBand.ofGrade(1), AralGradeBand.g1to3);
    expect(AralGradeBand.ofGrade(10), AralGradeBand.g7to10);
    expect(AralGradeBand.ofGrade(11), isNull);
    expect(AralGradeBand.ofGrade(0), isNull);
    expect(AralGradeBand.g4to6.contains(4), isTrue);
    expect(AralGradeBand.g4to6.contains(7), isFalse);
    expect(AralGradeBand.fromString('7-10'), AralGradeBand.g7to10);
    expect(() => AralGradeBand.fromString('1-2'), throwsArgumentError);
  });

  test('a class takes 15 active learners', () {
    expect(check(others: 14), isNull);
    expect(check(others: 15), AralPlacementProblem.full);
  });

  test('program, band and school are checked', () {
    expect(check(program: AralClassProgram.ks2Plus), AralPlacementProblem.programMismatch);
    expect(
        check(target: rose.copyWith(program: AralClassProgram.ks2Basic, gradeBand: AralGradeBand.g4to6), program: AralClassProgram.ks2Basic),
        AralPlacementProblem.gradeOutsideBand);
    expect(check(schoolId: 2), AralPlacementProblem.otherSchoolOrYear);
    expect(check(schoolYear: '2027-2028'), AralPlacementProblem.otherSchoolOrYear);
  });

  test('the first problem wins, in the cloud check\'s order', () {
    expect(check(schoolId: 2, program: AralClassProgram.ks1, grade: 2, others: 15), AralPlacementProblem.otherSchoolOrYear);
    expect(check(program: AralClassProgram.ks1, grade: 2, others: 15), AralPlacementProblem.programMismatch);
    expect(check(grade: 5, others: 15), AralPlacementProblem.gradeOutsideBand);
  });

  test('messages', () {
    String msg(AralPlacementProblem p, {int grade = 7, AralClassProgram program = AralClassProgram.ks3Basic}) =>
        aralPlacementMessage(p, learner: 'DELA CRUZ, JUAN', target: rose, grade: grade, program: program);
    expect(msg(AralPlacementProblem.full), 'Class "7-Rose" already has 15 active ARAL learners.');
    expect(msg(AralPlacementProblem.programMismatch, program: AralClassProgram.ks2Plus),
        'DELA CRUZ, JUAN is in KS2 Plus; class "7-Rose" is KS3 Basic.');
    expect(msg(AralPlacementProblem.gradeOutsideBand, grade: 5),
        'DELA CRUZ, JUAN is in Grade 5; class "7-Rose" takes Grades 7-10.');
    expect(msg(AralPlacementProblem.otherSchoolOrYear), 'Class "7-Rose" belongs to another school or school year.');
  });

  test('a class row round-trips', () {
    final c = AralClass.fromMap({
      'id': -3, 'school_id': 1, 'school_year': '2026-2027', 'class_name': '7-Rose', 'program': 'ks3_basic',
      'grade_band': '7-10', 'tutor_id': 'u1', 'room': 'Rm 4', 'schedule': null, 'notes': null,
      'created_by': 'c1', 'created_at': '2026-10-24T00:00:00Z', 'updated_at': '2026-10-24T00:00:00Z',
    });
    expect(c.program, AralClassProgram.ks3Basic);
    expect(c.gradeBand, AralGradeBand.g7to10);
    expect(c.toMap()['program'], 'ks3_basic');
    expect(c.toMap()['grade_band'], '7-10');
    expect(c.copyWith(tutorId: () => null).tutorId, isNull);
    expect(c.copyWith(room: () => 'Rm 5').room, 'Rm 5');
    expect(c.copyWith().tutorId, 'u1');
  });
}
