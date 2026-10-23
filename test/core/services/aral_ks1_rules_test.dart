// ARAL Key Stage 1 rules from DepEd Memorandum 064 s. 2025 (owner 2026-10-23):
// who qualifies, which CRLA counts, the school's "extended" switch.
import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/crla_result.dart';
import 'package:basa_capstone/core/services/aral_rules.dart';
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Low and High Emerging qualify; Developing and Transitioning only in the extended program', () {
    for (final p in [crlaLowEmerging, crlaHighEmerging]) {
      expect(aralCrlaQualifies(p), isTrue, reason: p);
      expect(aralCrlaQualifies(p, extended: true), isTrue, reason: p);
    }
    for (final p in [crlaDeveloping, crlaTransitioning]) {
      expect(aralCrlaQualifies(p), isFalse, reason: p);
      expect(aralCrlaQualifies(p, extended: true), isTrue, reason: p);
    }
    expect(aralCrlaQualifies(crlaAtGradeLevel, extended: true), isFalse);
    expect(aralCrlaQualifies('not a profile', extended: true), isFalse);
  });

  test('the CRLA that counts: G1 Mother Tongue else Filipino, G2 Filipino, G3 English', () {
    expect(aralCrlaBasisVariant(1, {'mt', 'fil'}), 'mt');
    expect(aralCrlaBasisVariant(1, {'fil', 'eng'}), 'fil');
    expect(aralCrlaBasisVariant(1, {}), 'fil');
    expect(aralCrlaBasisVariant(2, {'mt', 'fil', 'eng'}), 'fil');
    expect(aralCrlaBasisVariant(2, {'eng'}), 'fil'); // no Filipino result yet: nothing counts
    expect(aralCrlaBasisVariant(3, {'fil', 'eng'}), 'eng');
    expect(aralCrlaBasisVariant(3, {'fil'}), 'eng');
  });

  test("reports and trends read the grade's CRLA language too (aralCrlaLearnerProfile)", () {
    CrlaResult r(String variant, String profile, {int attempt = 1, CrlaRound round = CrlaRound.bosy,
            String day = '2026-08-20'}) =>
        CrlaResult(assessmentId: attempt, studentId: 1, schoolId: 1, sectionId: 1, schoolYear: '2026-2027',
            subjectVariant: variant, language: variant, round: round, attemptNo: attempt, assessedAt: day,
            readingProfile: profile);
    final g3 = [r('fil', crlaLowEmerging), r('eng', crlaAtGradeLevel)];
    // Grade 3 counts English only, not the weaker Filipino.
    expect(aralCrlaLearnerProfile(g3, CrlaRound.bosy, '2026-12-31', grade: 3), crlaAtGradeLevel);
    // An explicit variant filter (dashboard trend) still reads that variant.
    expect(aralCrlaLearnerProfile(g3, CrlaRound.bosy, '2026-12-31', grade: 3, variant: 'fil'), crlaLowEmerging);
    // Grade 2: Filipino; none yet -> null.
    expect(aralCrlaLearnerProfile([r('eng', crlaLowEmerging)], CrlaRound.bosy, '2026-12-31', grade: 2), isNull);
    // Grade 1: Mother Tongue when there is one; latest attempt; nothing after the report date.
    final g1 = [
      r('fil', crlaLowEmerging, round: CrlaRound.mosy),
      r('mt', crlaHighEmerging, round: CrlaRound.mosy),
      r('mt', crlaDeveloping, round: CrlaRound.mosy, attempt: 2, day: '2027-01-10'),
    ];
    expect(aralCrlaLearnerProfile(g1, CrlaRound.mosy, '2026-12-31', grade: 1), crlaHighEmerging);
    expect(aralCrlaLearnerProfile(g1, CrlaRound.mosy, '2027-01-31', grade: 1), crlaDeveloping);
  });

  test('the CRLA rank key keeps the view\'s fraction of words read (F12)', () {
    // crla_results.pct_correct_words_read is words_read / word_count (0-1).
    expect(AralRankKey.crla(pctCorrectWordsRead: 0.625, comprehensionCorrect: 4, wpm: 40).wordRecognition, 0.625);
    expect(AralRankKey.crla().wordRecognition, 0);
  });

  test('ks1_extended is off unless set to true', () {
    expect(AralProgramSettings.fromMap({}).ks1Extended, isFalse);
    expect(AralProgramSettings.fromMap({'ks1_extended': true}).ks1Extended, isTrue);
    expect(AralProgramSettings.fromMap({'ks1_extended': 'yes'}).ks1Extended, isFalse);
    expect(AralProgramSettings.fromMap({'foundational_program': true}).foundationalProgram, isTrue);
  });
}
