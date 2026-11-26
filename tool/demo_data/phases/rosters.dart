// Rosters phase (demo-data plan Task 7): one generated SF1 per section,
// imported as the school's coordinator (trial first: a conflict, a move or a
// return stops the run), then the section's adviser and tutors. Resumable per
// section (state step "rosters-<year>.<school>-G<grade>"); an import run again
// only reports the learners as already enrolled.
import 'dart:io';

import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';

import '../session.dart';
import '../sf1_files.dart';
import '../state.dart';
import '../world.dart';

/// The state step of [y]'s rosters (`rosters-2025`, `rosters-2026`).
String rostersStep(DemoYear y) => 'rosters-${y.label.substring(0, 4)}';

String coordinatorOf(String schoolCode) => schoolCode == 'NCES-DEMO' ? 'coord.es' : 'coord.hs';

/// Imports every section of [y]; [exclude] = LRNs left off the files (the
/// 2026-2027 re-imports, Task 11).
Future<void> runRosters(DemoSession s, DemoState st, DemoWorld w, DemoYear y,
    {Set<String> exclude = const {}}) async {
  for (final section in w.sections.where((x) => x.year == y)) {
    final step = '${rostersStep(y)}.${section.schoolCode}-${demoSectionKey(section)}';
    if (st.done(step)) continue;
    final learners = [for (final l in w.inSection(section)) if (!exclude.contains(l.lrn)) l];
    final dev = await s.as(coordinatorOf(section.schoolCode));
    final admin = dev.admin!;
    final path = writeDemoSf1(s.dir, section, learners, await Sf1ColumnMap.load(dev.dir.path));

    final trial = await admin.importVm.trial(path);
    if (trial.wouldConflict + trial.wouldMove + trial.wouldReturn > 0 || trial.rowWarnings.isNotEmpty) {
      throw StateError('${section.name} (${y.label}): the trial has ${trial.wouldConflict} conflict(s), '
          '${trial.wouldMove} move(s), ${trial.wouldReturn} return(s), warnings ${trial.rowWarnings}');
    }
    final r = await admin.importVm.import(path);
    if (r.conflicts + r.waiting > 0 || r.sectionId == null) {
      throw StateError('${section.name} (${y.label}): import gave ${r.conflicts} conflict(s), ${r.waiting} waiting');
    }
    final sectionId = r.sectionId!;
    await st.putId(demoSectionIdKey(section), sectionId);

    final users = admin.userVm;
    Future<String> idOf(String key) async => (await users.findByEmail(demoAccount(key).email))!.id;
    await dev.shared.sectionVm.setAdviser(sectionId,
        name: section.adviserName,
        userId: section.adviserAccount == null ? null : await idOf(section.adviserAccount!));
    for (final tutor in section.tutorAccounts) {
      try {
        await admin.tutorSectionVm.assign(tutorId: await idOf(tutor), sectionId: sectionId);
      } on ViewModelException catch (e) {
        if (!e.message.contains('already assigned')) rethrow;
      }
    }
    stdout.writeln('  ${section.schoolCode} ${section.name}: ${learners.length} learners (new ${r.inserted}, '
        'continuing ${r.continuing}, already enrolled ${r.alreadyEnrolled}), section $sectionId, '
        'tutors ${section.tutorAccounts.join(', ')}');
    await st.markDone(step);
  }
}
