// The round plan of the CRLA and Phil-IRI phases (demo-data plan Task 11):
// the default is the 2025-2026 behaviour; a plan narrows rounds, learners and
// who assesses.
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/round_plan.dart';
import '../../../tool/demo_data/world.dart';

void main() {
  final w = DemoWorld.build();
  final section = w.sections.firstWhere((s) => s.year == DemoYear.y2026 && s.grade == 8);
  final l = w.inSection(section).first;

  test('default: every round and learner, the section tutor, a GST, typed time', () {
    const p = DemoRoundPlan();
    expect(p.runs('bosy') && p.runs('mosy1') && p.runs('eosy'), isTrue);
    expect(p.learnersOf(w, section), w.inSection(section));
    expect(p.assesses(l, 'bosy'), isTrue);
    expect(p.assessorOf(l, section, 'bosy'), section.tutorAccounts.first);
    expect(p.gst(l), isTrue);
    expect(p.timedRounds, isEmpty);
  });

  test('a plan narrows rounds, learners and the assessor', () {
    final p = DemoRoundPlan(
      rounds: const {'mosy1'},
      roster: (s) => [l],
      assess: (x, r) => false,
      classTutor: (x, r) => 'tutor3.hs',
      recordGst: (x) => false,
      timedRounds: const {'mosy1'},
    );
    expect(p.runs('bosy'), isFalse);
    expect(p.runs('mosy1'), isTrue);
    expect(p.learnersOf(w, section), [l]);
    expect(p.assesses(l, 'mosy1'), isFalse);
    expect(p.assessorOf(l, section, 'mosy1'), 'tutor3.hs');
    expect(p.gst(l), isFalse);
  });
}
