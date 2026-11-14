// lib/core/console/commands/sf1_leaver_admin_commands.dart
//
// Admin build only (named *_admin_commands.dart, so tool/check_tutor_imports.dart
// treats it as admin): learners who are no longer on a section's SF1 (spec
// docs/superpowers/specs/2026-11-12-sf1-leavers-design.md). One action per
// command; everything goes through LearnerLeaversViewModel, which checks the
// caller, talks to the server functions and words every message.
//
// The superadmin has no school of their own: the commands that list a
// school's learners take `school=<id>` (a school-bound user may leave it out).
// Only learner-anonymize takes a confirm code (owner 2026-11-12).

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/enrollment.dart' show EnrollmentStatus;
import '../../models/sf1_missing_learner.dart';
import '../../../viewmodels/learner_leavers_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

/// Splits `school=<id>` off the arguments: (the other arguments, the school).
(List<String>, int?) _school(List<String> args, String usage) {
  int? school;
  final rest = <String>[];
  for (final a in args) {
    if (a.toLowerCase().startsWith('school=')) {
      if (school != null) throw _Usage('school= given twice.\n$usage');
      school = int.tryParse(a.substring(7)) ?? (throw _Usage('Invalid school: "${a.substring(7)}"\n$usage'));
    } else {
      rest.add(a);
    }
  }
  return (rest, school);
}

int _int(String s, String what, String usage) => int.tryParse(s) ?? (throw _Usage('Invalid $what: "$s"\n$usage'));

String _missingLine(Sf1MissingLearner m) => '  enrollment ${m.enrollmentId} | student ${m.studentId} | LRN ${m.lrn} | '
    '${m.name}${m.sectionId == null ? '' : ' | section ${m.sectionId} ${m.sectionName ?? ''}'.trimRight()}';

void registerSf1LeaverCommands(ConsoleRegistry registry, LearnerLeaversViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } on ViewModelException catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('sf1-missing',
      'sf1-missing [sectionId] [school=<id>] — learners still active but not on their section\'s last imported '
          'SF1, school-wide or of one section (undecided: archive, move or keep them; the superadmin names the '
          'school; online)', (args) async {
    const usage = 'Usage: sf1-missing [sectionId] [school=<id>]';
    final (rest, school) = _school(args, usage);
    if (rest.length > 1) throw const _Usage(usage);
    final section = rest.isEmpty ? null : _int(rest[0], 'sectionId', usage);
    final list = await vm.missing(sectionId: section, schoolId: school);
    if (list.isEmpty) {
      return section == null
          ? 'No learner is missing from a section\'s last imported SF1.'
          : 'No learner of section $section is missing from its last imported SF1.';
    }
    return [
      'Not on the latest SF1 - undecided (${list.length}):',
      for (final m in list) _missingLine(m),
      'Decide per learner: sf1-archive <enrollmentId> transferred|dropped, sf1-move <enrollmentId> <sectionId>; '
          'a learner left as is stays active.',
    ].join('\n');
  });

  add('sf1-archive',
      'sf1-archive <enrollmentId> transferred|dropped [note...] — archive a learner who transferred out or dropped '
          'out (records kept; their active ARAL entry is exited too; online)', (args) async {
    const usage = 'Usage: sf1-archive <enrollmentId> transferred|dropped [note...]';
    if (args.length < 2) throw const _Usage(usage);
    final id = _int(args[0], 'enrollmentId', usage);
    final reason = switch (args[1].toLowerCase()) {
      'transferred' => EnrollmentStatus.transferredOut,
      'dropped' => EnrollmentStatus.droppedOut,
      _ => throw _Usage('The reason is transferred or dropped (got "${args[1]}").\n$usage'),
    };
    final note = args.length > 2 ? args.sublist(2).join(' ') : null;
    return (await vm.archive(id, reason, note: note)).message;
  });

  add('sf1-move',
      'sf1-move <enrollmentId> <sectionId> [school=<id>] — move a learner to another section of the same school, '
          'year and grade with this year\'s CRLA, Phil-IRI and GST records (from the old section\'s missing list, '
          'or confirming a "moving from" row of the new section\'s SF1; the superadmin names the school; online)',
      (args) async {
    const usage = 'Usage: sf1-move <enrollmentId> <sectionId> [school=<id>]';
    final (rest, school) = _school(args, usage);
    if (rest.length != 2) throw const _Usage(usage);
    final id = _int(rest[0], 'enrollmentId', usage);
    final to = _int(rest[1], 'sectionId', usage);
    // The ViewModel decides where the move was decided (sf1_missing or
    // sf1_incoming) from the learner's own enrollment.
    return (await vm.move(id, to, schoolId: school)).message;
  });

  add('sf1-restore',
      'sf1-restore <enrollmentId> [sectionId] — make an archived learner active again, in their own section or '
          'moved into another of the same grade (ARAL is not restored; online)', (args) async {
    const usage = 'Usage: sf1-restore <enrollmentId> [sectionId]';
    if (args.isEmpty || args.length > 2) throw const _Usage(usage);
    final id = _int(args[0], 'enrollmentId', usage);
    final to = args.length == 2 ? _int(args[1], 'sectionId', usage) : null;
    return (await vm.restore(id, toSectionId: to)).message;
  });

  add('learner-anonymize-preview',
      'learner-anonymize-preview [school=<id>] — learners archived long enough to be anonymized (their latest school '
          'year archived more than archive_keep_months ago and ended; earlier years do not count) and the confirm code '
          'learner-anonymize needs (online)', (args) async {
    const usage = 'Usage: learner-anonymize-preview [school=<id>]';
    final (rest, school) = _school(args, usage);
    if (rest.isNotEmpty) throw const _Usage(usage);
    final p = await vm.anonymizePreview(schoolId: school);
    return [
      if (p.learners.isEmpty)
        'No learner can be anonymized now.'
      else ...[
        'Can be anonymized (${p.learners.length}):',
        for (final l in p.learners)
          '  student ${l.studentId} | ${l.lrn == null ? 'not on this device' : 'LRN ${l.lrn} | ${l.name}'} | '
              'archived ${l.leftOn ?? '-'} | school year ${l.schoolYear}',
        'Anonymizing clears their name, LRN, birth date and contact details for good (sex and records are '
            'kept); they cannot be matched again.',
      ],
      'confirm code: ${p.code}',
    ].join('\n');
  });

  add('learner-anonymize',
      'learner-anonymize <code> [school=<id>] — anonymize every learner the preview listed (the code from '
          'learner-anonymize-preview; refused when the list changed; online)', (args) async {
    const usage = 'Usage: learner-anonymize <code> [school=<id>]';
    final (rest, school) = _school(args, usage);
    if (rest.length != 1) throw const _Usage(usage);
    await vm.anonymize(rest[0], schoolId: school);
    return vm.lastMessage ?? 'Done.';
  });
}
