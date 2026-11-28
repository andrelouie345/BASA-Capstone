// One-time fixes to a demo world built by an earlier version of the builder.
//   section-names  sections were named "Grade 8 - Acacia"; screens show
//                  "Grade 8 · <name>", so the grade showed twice (walkthrough
//                  finding 1, 2026-11-27). Each school's coordinator renames
//                  them to "Acacia" (SectionViewModel.update, online). A world
//                  built since then already has the short names: nothing to do.
import 'dart:io';

import '../session.dart';
import '../state.dart';
import '../world.dart';
import 'rosters.dart';

const fixesStep = 'fixes';

typedef FixPart = ({String name, Future<void> Function(DemoSession s, DemoState st, DemoWorld w, DateTime today) run});

final List<FixPart> fixParts = [
  (name: '$fixesStep.section-names', run: (s, st, w, today) => _sectionNames(s, st, w)),
];

Future<void> _sectionNames(DemoSession s, DemoState st, DemoWorld w) async {
  var renamed = 0, kept = 0;
  for (final school in demoSchools) {
    final dev = await s.as(coordinatorOf(school.code));
    final vm = dev.shared.sectionVm;
    for (final section in w.sections.where((x) => x.schoolCode == school.code)) {
      final id = st.ids[demoSectionIdKey(section)];
      if (id == null) continue; // not built yet
      final now = await vm.getById(id);
      if (now == null) throw StateError('section $id (${section.name}) is not on ${coordinatorOf(school.code)}\'s device');
      if (now.sectionName == section.name) {
        kept++;
        continue;
      }
      if (now.sectionName != demoOldSectionName(section)) {
        throw StateError('section $id is named "${now.sectionName}", expected "${demoOldSectionName(section)}"');
      }
      await vm.update(id: id, schoolYear: now.schoolYear, gradeLevel: now.gradeLevel, sectionName: section.name);
      renamed++;
    }
    await dev.shared.syncVm.pull();
  }
  stdout.writeln('  section names: $renamed renamed ("Grade N - X" -> "X"), $kept already short');
}
