// The no-improvement rule for ARAL learners (spec
// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D2-D3).
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_progress.dart';
import 'package:basa_capstone/core/services/aral_checkin_rules.dart';
import 'package:basa_capstone/core/services/aral_effectiveness_rules.dart';
import 'package:flutter_test/flutter_test.dart';

AralEnrollment _enrollment({String? exitedOn}) => AralEnrollment(
      id: 1,
      studentId: 1,
      schoolId: 1,
      sectionId: 1,
      schoolYear: '2026-2027',
      keyStage: AralKeyStage.ks3,
      enteredOn: '2026-07-01',
      exitedOn: exitedOn,
      basisSource: AralBasisSource.philIri,
      basisRound: 'bosy',
    );

AralLearnerProgress _row(AralProgressChange change,
        {String instrument = AralLearnerProgress.philIri,
        String startProfile = 'Frustration',
        String? latestRound = 'mosy1',
        String? latestProfile = 'Frustration',
        String? exitedOn}) =>
    AralLearnerProgress(
      enrollment: _enrollment(exitedOn: exitedOn),
      learnerName: 'CRUZ, Ana',
      grade: instrument == AralLearnerProgress.crla ? 2 : 7,
      instrument: instrument,
      startRound: 'bosy',
      startProfile: startProfile,
      latestRound: latestRound,
      latestProfile: latestProfile,
      latestAssessedOn: latestRound == null ? null : '2026-10-05',
      change: change,
    );

AralCheckinOutcome _checkin(int correct, {bool complete = true}) =>
    AralCheckinOutcome(afterSession: 16, score: AralCheckinScore(correct, 20, 20), passPct: 75, complete: complete);

void main() {
  List<AralNoImprovementReason> reasons(AralLearnerProgress p, {int attended = 16, AralCheckinOutcome? checkin}) =>
      aralNoImprovementReasons(p, attendedBeforeLatest: attended, minAttended: 16, latestCheckin: checkin);

  test('same after enough sessions', () {
    final r = reasons(_row(AralProgressChange.same));
    expect(r.map((x) => x.kind), [AralNoImprovementKind.round]);
    expect(r.single.message, 'Same since BOSY: Frustration -> Frustration (MOSY #1)');
  });

  test('down', () {
    final r = reasons(_row(AralProgressChange.down,
        instrument: AralLearnerProgress.crla,
        startProfile: 'Developing Reader',
        latestRound: 'mosy',
        latestProfile: 'High Emerging Reader'));
    expect(r.single.message, 'Down since BOSY: Developing Reader -> High Emerging Reader (MOSY)');
  });

  test('too few attended', () {
    expect(reasons(_row(AralProgressChange.same), attended: 15), isEmpty);
  });

  test('up, not assessed yet and no starting result give no round reason', () {
    expect(reasons(_row(AralProgressChange.up, latestProfile: 'Instructional')), isEmpty);
    expect(reasons(_row(AralProgressChange.notAssessedYet, latestRound: null, latestProfile: null)), isEmpty);
    expect(reasons(_row(AralProgressChange.noStartingResult)), isEmpty);
  });

  test('failed check-in', () {
    final r = reasons(_row(AralProgressChange.up), checkin: _checkin(9));
    expect(r.map((x) => x.kind), [AralNoImprovementKind.checkin]);
    expect(r.single.message, 'Check-in after session 16: 45%, pass mark 75%');
  });

  test('incomplete check-in ignored, passed check-in gives none', () {
    expect(reasons(_row(AralProgressChange.up), checkin: _checkin(9, complete: false)), isEmpty);
    expect(reasons(_row(AralProgressChange.up), checkin: _checkin(15)), isEmpty);
  });

  test('both reasons, round first', () {
    final r = reasons(_row(AralProgressChange.same), checkin: _checkin(9));
    expect(r.map((x) => x.kind), [AralNoImprovementKind.round, AralNoImprovementKind.checkin]);
  });

  test('exited learner', () {
    expect(reasons(_row(AralProgressChange.same, exitedOn: '2026-10-20'), checkin: _checkin(9)), isEmpty);
  });
}
