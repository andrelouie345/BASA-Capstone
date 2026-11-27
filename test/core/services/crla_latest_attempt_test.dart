// One CRLA "latest attempt" rule (spec docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md D3):
// attempt_no restarts per section, so a learner moved mid-year has an attempt 2
// in the old section and an attempt 1 in the new one. Latest = date, then
// attempt number, then the later-made row.
import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/crla_result.dart';
import 'package:basa_capstone/core/services/aral_rules.dart';
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:flutter_test/flutter_test.dart';

CrlaResult _r(int id, int section, int attempt, String day, String profile) => CrlaResult(
    assessmentId: id, studentId: 1, schoolId: 1, sectionId: section, schoolYear: '2026-2027',
    subjectVariant: 'fil', language: 'Tagalog', round: CrlaRound.bosy, attemptNo: attempt, assessedAt: day,
    readingProfile: profile);

void main() {
  final oldSection = _r(10, 1, 2, '2026-08-01', crlaLowEmerging);
  final newSection = _r(20, 2, 1, '2026-09-15', crlaDeveloping);

  test('moved mid-year: the new section\'s attempt 1 (later date) beats the old section\'s attempt 2', () {
    expect(crlaLatestAttempt([oldSection, newSection])!.assessmentId, 20);
    expect(crlaLatestAttempt([newSection, oldSection])!.assessmentId, 20);
  });

  test('same day: attempt number, then the later-made row', () {
    expect(crlaLatestAttempt([_r(1, 1, 2, '2026-09-15', ''), _r(2, 2, 1, '2026-09-15', '')])!.assessmentId, 1);
    // A row made on this device (id < 0) is later than any pulled row.
    expect(crlaLatestAttempt([_r(40, 1, 1, '2026-09-15', ''), _r(-3, 2, 1, '2026-09-15', '')])!.assessmentId, -3);
    // Among device rows the more negative is later; among pulled rows the higher.
    expect(crlaLatestAttempt([_r(-3, 1, 1, '2026-09-15', ''), _r(-7, 2, 1, '2026-09-15', '')])!.assessmentId, -7);
    expect(crlaLatestAttempt([_r(41, 1, 1, '2026-09-15', ''), _r(40, 2, 1, '2026-09-15', '')])!.assessmentId, 41);
  });

  test('empty -> null', () => expect(crlaLatestAttempt(const []), isNull));

  test('aralCrlaLearnerProfile follows the latest attempt for a moved learner', () {
    expect(aralCrlaLearnerProfile([oldSection, newSection], CrlaRound.bosy, '2026-12-31', grade: 2), crlaDeveloping);
  });
}
