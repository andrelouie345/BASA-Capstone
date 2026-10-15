// lib/core/console/commands/aral_commands.dart

/// Commands for the ARAL-Reading roster (local, offline-first): BASA's
/// proposal, putting learners on the roster, their program, tutor, exit and
/// notes. One action per command; the ViewModel does the checks.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import '../../models/aral_enrollment.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

AralKeyStage? _ks(String raw) => switch (raw.toLowerCase()) {
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

String _line(AralEnrollment e, Map<int, String> names) {
  final who = names[e.studentId] ?? 'student ${e.studentId}';
  final status = e.isActive ? 'active' : 'exited ${e.exitedOn} (${e.exitReason?.value})';
  final suggested = e.suggestedKeyStage == null
      ? 'added by hand'
      : 'suggested ${e.suggestedTrack == null ? e.suggestedKeyStage!.label : '${e.suggestedKeyStage!.label} ${e.suggestedTrack!.label}'}';
  final basis = e.basisLevel == null ? e.basisSource.value : '${e.basisSource.value} ${e.basisRound ?? ''} ${e.basisLevel}';
  return '#${e.id} | $who (${e.studentId}) | ${e.programLabel} | $status | tutor ${e.tutorId ?? '-'} | '
      'basis: ${basis.trim()} | $suggested${e.notes == null ? '' : ' | notes: ${e.notes}'}';
}

void registerAralCommands(ConsoleRegistry registry, AralViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          final out = await handler(args);
          final warning = vm.lastWarning;
          return warning == null ? out : '$out\nWarning: $warning';
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-propose',
      'aral-propose <sectionId> <schoolYear> [optional] — who BASA proposes for ARAL-Reading and in which program '
          '("optional" adds KS1 Developing/Transitioning and KS2-3 Instructional readers)', (args) async {
    const usage = 'Usage: aral-propose <sectionId> <schoolYear> [optional]';
    if (args.length < 2) throw const _Usage(usage);
    final list = await vm.propose(
        sectionId: _int(args[0], 'sectionId'), schoolYear: args[1], includeOptional: args.contains('optional'));
    if (list.isEmpty) return 'No actively enrolled learners in that section.';
    final count = {for (final s in AralCandidateStatus.values) s: list.where((c) => c.status == s).length};
    final lines = [
      for (final c in list)
        '${c.student.id} | ${c.name} | ${c.status.name}'
            '${c.suggestion == null ? '' : ' -> ${c.suggestion!.label}'} | ${c.reason}',
    ];
    return '${lines.join('\n')}\n'
        '${count[AralCandidateStatus.proposed]} proposed, ${count[AralCandidateStatus.notQualified]} not qualifying, '
        '${count[AralCandidateStatus.noResult]} without a result, ${count[AralCandidateStatus.enrolled]} already in ARAL.';
  });

  add('aral-enroll',
      'aral-enroll <sectionId> <schoolYear> <studentId> [ks1|ks2|ks3] [basic|plus] [tutor=<userId>] [optional] '
          '— put a learner on the ARAL roster (no program = BASA\'s proposal; give one to change it or to add '
          'a learner by hand)', (args) async {
    const usage = 'Usage: aral-enroll <sectionId> <schoolYear> <studentId> [ks1|ks2|ks3] [basic|plus] [tutor=<userId>] [optional]';
    if (args.length < 3) throw const _Usage(usage);
    AralKeyStage? ks;
    AralTrack? track;
    String? tutor;
    for (final a in args.skip(3)) {
      if (_ks(a) != null) {
        ks = _ks(a);
      } else if (_track(a) != null) {
        track = _track(a);
      } else if (a.startsWith('tutor=')) {
        tutor = a.substring(6);
      } else if (a != 'optional') {
        throw _Usage('Unknown option "$a".\n$usage');
      }
    }
    final e = await vm.enroll(
      sectionId: _int(args[0], 'sectionId'),
      schoolYear: args[1],
      studentId: _int(args[2], 'studentId'),
      keyStage: ks,
      track: track,
      tutorId: tutor,
      includeOptional: args.contains('optional'),
    );
    return 'On the ARAL roster: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-enroll-proposed',
      'aral-enroll-proposed <sectionId> <schoolYear> [optional] [tutor=<userId>] — confirm every proposal of the '
          'section as suggested', (args) async {
    const usage = 'Usage: aral-enroll-proposed <sectionId> <schoolYear> [optional] [tutor=<userId>]';
    if (args.length < 2) throw const _Usage(usage);
    final tutor = args.where((a) => a.startsWith('tutor=')).map((a) => a.substring(6)).firstOrNull;
    final created = await vm.enrollProposed(
      sectionId: _int(args[0], 'sectionId'),
      schoolYear: args[1],
      includeOptional: args.contains('optional'),
      tutorId: tutor,
    );
    if (created.isEmpty) return 'Nobody new to add (no proposals, or all are already in ARAL).';
    final names = await vm.learnerNames(created.first.sectionId);
    return 'Added ${created.length} learner(s):\n${created.map((e) => _line(e, names)).join('\n')}';
  });

  add('aral-roster',
      'aral-roster <sectionId> [schoolYear] | aral-roster school <schoolId> [schoolYear] | '
          'aral-roster tutor [userId] [schoolYear] — the ARAL roster', (args) async {
    const usage = 'Usage: aral-roster <sectionId> [schoolYear] | school <schoolId> [schoolYear] | tutor [userId] [schoolYear]';
    if (args.isEmpty) throw const _Usage(usage);
    List<AralEnrollment> list;
    if (args[0] == 'school') {
      if (args.length < 2) throw const _Usage(usage);
      list = await vm.schoolRoster(schoolId: _int(args[1], 'schoolId'), schoolYear: args.elementAtOrNull(2));
    } else if (args[0] == 'tutor') {
      final rest = args.skip(1).toList();
      final year = rest.where((a) => RegExp(r'^\d{4}\s*-\s*\d{4}$').hasMatch(a)).firstOrNull;
      final id = rest.where((a) => a != year).firstOrNull;
      list = await vm.tutorRoster(tutorId: id, schoolYear: year);
    } else {
      list = await vm.roster(sectionId: _int(args[0], 'sectionId'), schoolYear: args.elementAtOrNull(1));
    }
    if (list.isEmpty) return 'Nobody on that ARAL roster.';
    final names = <int, String>{};
    for (final section in list.map((e) => e.sectionId).toSet()) {
      names.addAll(await vm.learnerNames(section));
    }
    final active = list.where((e) => e.isActive).length;
    return '${list.map((e) => _line(e, names)).join('\n')}\n${list.length} on the roster, $active active.';
  });

  add('aral-tutors', 'aral-tutors <schoolId> <schoolYear> — tutors who can be assigned, with their ARAL load',
      (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-tutors <schoolId> <schoolYear>');
    final list = await vm.tutors(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No active tutors in that school.';
    return list
        .map((t) => '${t.$1.id} | ${t.$1.fullName} | ${t.$2} active ARAL learner(s)'
            '${t.$2 > aralTutorLoad ? ' (over $aralTutorLoad)' : ''}')
        .join('\n');
  });

  add('aral-placement', 'aral-placement <enrollmentId> <ks1|ks2|ks3> [basic|plus] — change the learner\'s program',
      (args) async {
    const usage = 'Usage: aral-placement <enrollmentId> <ks1|ks2|ks3> [basic|plus]';
    if (args.length < 2) throw const _Usage(usage);
    final ks = _ks(args[1]) ?? (throw const _Usage(usage));
    final track = args.length > 2 ? (_track(args[2]) ?? (throw const _Usage(usage))) : null;
    final e = await vm.setPlacement(_int(args[0], 'enrollmentId'), ks, track);
    return 'Updated: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-tutor', 'aral-tutor <enrollmentId> <userId|-> — assign the learner\'s ARAL tutor ("-" removes it)',
      (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-tutor <enrollmentId> <userId|->');
    final e = await vm.assignTutor(_int(args[0], 'enrollmentId'), args[1] == '-' ? null : args[1]);
    return 'Updated: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-exit',
      'aral-exit <enrollmentId> <grade_level_ready|transferred_out|dropped_out|other> [YYYY-MM-DD] — record that '
          'the learner left ARAL (date defaults to today)', (args) async {
    const usage = 'Usage: aral-exit <enrollmentId> <grade_level_ready|transferred_out|dropped_out|other> [YYYY-MM-DD]';
    if (args.length < 2) throw const _Usage(usage);
    final reason = AralExitReason.values.where((r) => r.value == args[1]).firstOrNull ?? (throw const _Usage(usage));
    final date = args.length > 2 ? (DateTime.tryParse(args[2]) ?? (throw const _Usage(usage))) : null;
    final e = await vm.exit(_int(args[0], 'enrollmentId'), reason, on: date);
    return 'Updated: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-reactivate', 'aral-reactivate <enrollmentId> — undo an exit', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-reactivate <enrollmentId>');
    final e = await vm.reactivate(_int(args[0], 'enrollmentId'));
    return 'Updated: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-notes', 'aral-notes <enrollmentId> <text...|-> — set the notes ("-" clears them)', (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-notes <enrollmentId> <text...|->');
    final text = args.sublist(1).join(' ');
    final e = await vm.setNotes(_int(args[0], 'enrollmentId'), text == '-' ? null : text);
    return 'Updated: ${_line(e, await vm.learnerNames(e.sectionId))}';
  });

  add('aral-remove', 'aral-remove <enrollmentId> — remove a learner added by mistake (leaving ARAL is aral-exit)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-remove <enrollmentId>');
    await vm.remove(_int(args[0], 'enrollmentId'));
    return 'Removed ARAL enrollment ${args[0]}.';
  });
}
