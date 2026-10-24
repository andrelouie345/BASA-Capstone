// lib/core/console/commands/aral_admin_commands.dart
// Admin build only: the admin half of aral_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import '../../models/aral_enrollment.dart';
import 'aral_command_helpers.dart';

void registerAralAdminCommands(ConsoleRegistry registry, AralViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          vm.lastWarning = null; // only this command's notice
          final out = await handler(args);
          final warning = vm.lastWarning;
          return warning == null ? out : '$out\nWarning: $warning';
        } on AralUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-propose',
      'aral-propose <sectionId> <schoolYear> — who BASA proposes for ARAL-Reading (every learner below grade level, '
          'weakest first) and in which program', (args) async {
    const usage = 'Usage: aral-propose <sectionId> <schoolYear>';
    if (args.length < 2) throw const AralUsage(usage);
    final sectionId = aralInt(args[0], 'sectionId');
    final list = await vm.propose(sectionId: sectionId, schoolYear: args[1]);
    if (list.isEmpty) return 'No actively enrolled learners in that section.';
    final count = {for (final s in AralCandidateStatus.values) s: list.where((c) => c.status == s).length};
    // Ranked learners first (weakest first), then the rest in roster order.
    final ranked = list.where((c) => c.rank != null).toList()..sort((a, b) => a.rank!.compareTo(b.rank!));
    final lines = [
      for (final c in [...ranked, ...list.where((c) => c.rank == null)])
        '${c.rank == null ? '  ' : '#${c.rank}'} | ${c.student.id} | ${c.name} | ${c.status.name}'
            '${c.suggestion == null ? '' : ' -> ${c.suggestion!.label}'} | ${c.reason}',
    ];
    return '${lines.join('\n')}\n'
        '${count[AralCandidateStatus.proposed]} proposed, '
        '${count[AralCandidateStatus.notQualified]} at/above grade level, ${count[AralCandidateStatus.noResult]} '
        'without a result, ${count[AralCandidateStatus.enrolled]} already in ARAL.';
  });

  add('aral-enroll',
      'aral-enroll <sectionId> <schoolYear> <studentId> [foundational|ks1|ks2|ks3] [basic|plus] [class=<classId>] '
          '[entered=YYYY-MM-DD] — put a proposed learner on the ARAL roster (no program = BASA\'s proposal; give one to '
          'change it, or to add a learner with no result yet; with class= also placed when the class takes them; entry '
          'date defaults to today)', (args) async {
    const usage = 'Usage: aral-enroll <sectionId> <schoolYear> <studentId> [foundational|ks1|ks2|ks3] [basic|plus] '
        '[class=<classId>] [entered=YYYY-MM-DD]';
    if (args.length < 3) throw const AralUsage(usage);
    AralKeyStage? ks;
    AralTrack? track;
    int? classId;
    DateTime? entered;
    for (final a in args.skip(3)) {
      if (_ks(a) != null) {
        ks = _ks(a);
      } else if (_track(a) != null) {
        track = _track(a);
      } else if (a.startsWith('class=')) {
        classId = aralInt(a.substring(6), 'classId');
      } else if (a.startsWith('entered=')) {
        entered = strictDateArg(a.substring(8)) ?? (throw AralUsage('Invalid date in "$a".\n$usage'));
      } else {
        throw AralUsage('Unknown option "$a".\n$usage');
      }
    }
    final e = await vm.enroll(
      sectionId: aralInt(args[0], 'sectionId'),
      schoolYear: args[1],
      studentId: aralInt(args[2], 'studentId'),
      keyStage: ks,
      track: track,
      classId: classId,
      enteredOn: entered,
    );
    return 'On the ARAL roster: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  const referUsage = 'Usage: aral-refer <sectionId> <schoolYear> <studentId> <foundational|ks1|ks2|ks3> [basic|plus] '
      '"by=<who referred>" "reason=<why>" [class=<classId>] [entered=YYYY-MM-DD]';
  add('aral-refer',
      'aral-refer <sectionId> <schoolYear> <studentId> <foundational|ks1|ks2|ks3> [basic|plus] "by=<who>" '
          '"reason=<why>" [class=<classId>] [entered=YYYY-MM-DD] — put a learner a teacher referred on the ARAL roster '
          '(whatever their results; they exit only grade-level ready)', (args) async {
    if (args.length < 4) throw const AralUsage(referUsage);
    final ks = _ks(args[3]) ?? (throw const AralUsage(referUsage));
    AralTrack? track;
    String? by, reason;
    int? classId;
    DateTime? entered;
    for (final a in args.skip(4)) {
      if (_track(a) != null) {
        track = _track(a);
      } else if (a.startsWith('by=')) {
        by = a.substring(3);
      } else if (a.startsWith('reason=')) {
        reason = a.substring(7);
      } else if (a.startsWith('class=')) {
        classId = aralInt(a.substring(6), 'classId');
      } else if (a.startsWith('entered=')) {
        entered = strictDateArg(a.substring(8)) ?? (throw AralUsage('Invalid date in "$a".\n$referUsage'));
      } else {
        throw AralUsage('Unknown option "$a".\n$referUsage');
      }
    }
    final e = await vm.refer(
      sectionId: aralInt(args[0], 'sectionId'),
      schoolYear: args[1],
      studentId: aralInt(args[2], 'studentId'),
      keyStage: ks,
      track: track,
      referredBy: by ?? '',
      reason: reason ?? '',
      classId: classId,
      enteredOn: entered,
    );
    return 'On the ARAL roster: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-enroll-proposed',
      'aral-enroll-proposed <sectionId> <schoolYear> [class=<classId>] — confirm every proposal of the section as '
          'suggested (with class=, the weakest go into that class while it has room; the rest wait for a class)',
      (args) async {
    const usage = 'Usage: aral-enroll-proposed <sectionId> <schoolYear> [class=<classId>]';
    if (args.length < 2) throw const AralUsage(usage);
    final classArg = args.skip(2).where((a) => a.startsWith('class=')).map((a) => a.substring(6)).firstOrNull;
    final created = await vm.enrollProposed(
      sectionId: aralInt(args[0], 'sectionId'),
      schoolYear: args[1],
      classId: classArg == null ? null : aralInt(classArg, 'classId'),
    );
    if (created.isEmpty) return 'Nobody new to add (no proposals, or all are already in ARAL).';
    final names = await vm.learnerNames(created.first.sectionId);
    final classes = await vm.classNames(created.first.schoolId);
    return 'Added ${created.length} learner(s):\n${created.map((e) => aralLine(e, names, classes)).join('\n')}';
  });

  add('aral-update',
      'aral-update <sectionId> <schoolYear> | aral-update school <schoolId> <schoolYear> — apply the latest '
          'results: program changes and grade-level-ready exits (the UI runs this when the roster opens)', (args) async {
    const usage = 'Usage: aral-update <sectionId> <schoolYear> | aral-update school <schoolId> <schoolYear>';
    final List<AralUpdate> list;
    if (args.isNotEmpty && args[0] == 'school') {
      if (args.length < 3) throw const AralUsage(usage);
      list = await vm.applySchoolResults(schoolId: aralInt(args[1], 'schoolId'), schoolYear: args[2]);
    } else {
      if (args.length < 2) throw const AralUsage(usage);
      list = await vm.applyResults(sectionId: aralInt(args[0], 'sectionId'), schoolYear: args[1]);
    }
    if (list.isEmpty) return 'No active ARAL learners there.';
    final names = <int, String>{};
    for (final section in list.map((u) => u.before.sectionId).toSet()) {
      names.addAll(await vm.learnerNames(section));
    }
    final lines = [
      for (final u in list)
        '#${u.before.id} | ${names[u.before.studentId] ?? 'student ${u.before.studentId}'} | ${u.kind.name} | ${u.reason}',
    ];
    int n(AralUpdateKind k) => list.where((u) => u.kind == k).length;
    return '${lines.join('\n')}\n${n(AralUpdateKind.programChanged)} program change(s), '
        '${n(AralUpdateKind.exited)} exit(s), ${n(AralUpdateKind.refreshed)} newer result(s) with the same program, '
        '${n(AralUpdateKind.unchanged)} unchanged, ${n(AralUpdateKind.noResult)} without a finished result; '
        '${n(AralUpdateKind.unplaced)} waiting for a class, ${n(AralUpdateKind.programMismatch)} in a class of '
        'another program, ${n(AralUpdateKind.otherGrade)} in a class of another grade, '
        '${n(AralUpdateKind.otherSection)} in another section, ${n(AralUpdateKind.leftSchool)} '
        'left the school.';
  });

  add('aral-placement',
      'aral-placement <enrollmentId> <foundational|ks1|ks2|ks3> [basic|plus] — change the learner\'s program',
      (args) async {
    const usage = 'Usage: aral-placement <enrollmentId> <foundational|ks1|ks2|ks3> [basic|plus]';
    if (args.length < 2) throw const AralUsage(usage);
    final ks = _ks(args[1]) ?? (throw const AralUsage(usage));
    final track = args.length > 2 ? (_track(args[2]) ?? (throw const AralUsage(usage))) : null;
    final e = await vm.setPlacement(aralInt(args[0], 'enrollmentId'), ks, track);
    return 'Updated: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-move',
      'aral-move <enrollmentId> — follow the learner\'s SF1 section move inside the school (the class stays; a '
          'new grade other than the class\'s is flagged)', (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-move <enrollmentId>');
    final e = await vm.moveToSection(aralInt(args[0], 'enrollmentId'));
    return 'Updated: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-exit',
      'aral-exit <enrollmentId> <transferred_out|dropped_out|other|classroom_support> [YYYY-MM-DD] — record that the learner left '
          'ARAL (date defaults to today; grade-level-ready exits come from results)', (args) async {
    const usage = 'Usage: aral-exit <enrollmentId> <transferred_out|dropped_out|other|classroom_support> [YYYY-MM-DD]';
    if (args.length < 2) throw const AralUsage(usage);
    final reason = AralExitReason.values.where((r) => r.value == args[1]).firstOrNull ?? (throw const AralUsage(usage));
    final date = args.length > 2 ? (strictDateArg(args[2]) ?? (throw const AralUsage(usage))) : null;
    final e = await vm.exit(aralInt(args[0], 'enrollmentId'), reason, on: date);
    return 'Updated: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-reactivate', 'aral-reactivate <enrollmentId> — undo a transfer/drop-out/other/classroom-support exit', (args) async {
    if (args.isEmpty) throw const AralUsage('Usage: aral-reactivate <enrollmentId>');
    final e = await vm.reactivate(aralInt(args[0], 'enrollmentId'));
    return 'Updated: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-notes', 'aral-notes <enrollmentId> <text...|-> — set the notes ("-" clears them)', (args) async {
    if (args.length < 2) throw const AralUsage('Usage: aral-notes <enrollmentId> <text...|->');
    final text = args.sublist(1).join(' ');
    final e = await vm.setNotes(aralInt(args[0], 'enrollmentId'), text == '-' ? null : text);
    return 'Updated: ${aralLine(e, await vm.learnerNames(e.sectionId), await vm.classNames(e.schoolId))}';
  });

  add('aral-remove', 'aral-remove <enrollmentId> — remove a learner added by mistake (leaving ARAL is aral-exit)',
      (args) async {
    if (args.isEmpty) throw const AralUsage('Usage: aral-remove <enrollmentId>');
    await vm.remove(aralInt(args[0], 'enrollmentId'));
    return 'Removed ARAL enrollment ${args[0]}.';
  });
}

AralKeyStage? _ks(String raw) => switch (raw.toLowerCase()) {
      'foundational' => AralKeyStage.foundational,
      'ks1' => AralKeyStage.ks1,
      'ks2' => AralKeyStage.ks2,
      'ks3' => AralKeyStage.ks3,
      _ => null,
    };

AralTrack? _track(String raw) => switch (raw.toLowerCase()) {
      'basic' => AralTrack.basic,
      'plus' => AralTrack.plus,
      _ => null,
    };
