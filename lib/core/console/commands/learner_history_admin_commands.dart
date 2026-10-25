// lib/core/console/commands/learner_history_admin_commands.dart
// Admin build only: one learner's progress by school year (LearnerHistoryViewModel;
// spec docs/superpowers/specs/2026-10-25-learner-history-design.md).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/learner_history_viewmodel.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

void registerLearnerHistoryCommands(ConsoleRegistry registry, LearnerHistoryViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('learner-history', 'learner-history <studentId> — one learner\'s progress by school year (CRLA, Phil-IRI, '
      'ARAL, SRP)', (args) async {
    const usage = 'Usage: learner-history <studentId>';
    if (args.length != 1) throw const _Usage(usage);
    final id = int.tryParse(args[0]) ?? (throw const _Usage(usage));
    return _text(await vm.history(id));
  });

  add('learner-history-lrn', 'learner-history-lrn <lrn> — the same, found by LRN', (args) async {
    if (args.length != 1) throw const _Usage('Usage: learner-history-lrn <lrn>');
    return _text(await vm.historyByLrn(args[0]));
  });
}

String _text(LearnerHistory h) {
  final s = h.student;
  final out = StringBuffer('${s.lastName}, ${s.firstName} (LRN ${s.lrn})');
  if (h.scopeNote != null) out.write('\n${h.scopeNote}');
  if (h.years.isEmpty) out.write('\nNo records on this device.');
  for (final y in h.years) {
    out.write('\n== ${y.schoolYear} ==');
    for (final e in y.enrollments) {
      out.write('\n  Section: Grade ${e.gradeLevel} ${e.sectionName} (${e.schoolName}), ${e.status}');
    }
    for (final round in y.crla.entries) {
      for (final lang in round.value.entries) {
        out.write('\n  CRLA ${round.key.label} ${lang.key}: ${lang.value ?? 'no profile'}');
      }
    }
    for (final p in y.philIri) {
      final r = p.results;
      final g = r.gst;
      final rounds = [
        for (final round in r.rounds)
          if (round.profile != null) '${round.round.label} ${round.profile!.label}${round.given ? '' : ' (carried)'}',
      ];
      out.write('\n  Phil-IRI ${p.sectionName ?? 'section'} (section ${p.sectionId}): '
          'GST ${g == null ? 'none' : '${g.totalScore}/${g.maxScore}'}; '
          '${rounds.isEmpty ? 'no round results' : rounds.join(', ')}; '
          'end ${r.end == null ? 'none yet' : '${r.end!.round.label} ${r.end!.profile?.label ?? '-'}'}');
    }
    for (final a in y.aral) {
      final e = a.enrollment;
      final exited = e.exitedOn == null ? '' : ', exited ${e.exitedOn} (${e.exitReason?.value})';
      out.write('\n  ARAL ${e.programLabel}: class ${a.className ?? 'waiting for a class'}, '
          'tutor ${a.tutorName ?? 'none'}, entered ${e.enteredOn}$exited; ${a.attendance.label}; '
          'check-in 16 ${_checkin(a.checkin16)}, 32 ${_checkin(a.checkin32)}');
    }
    final srp = y.srp;
    if (srp != null) {
      out.write('\n  SRP: ${srp.className} (tutor ${srp.tutorName ?? 'none'}${srp.room == null ? '' : ', room ${srp.room}'})');
    }
    if (y.isEmpty) out.write('\n  No assessments recorded');
  }
  return out.toString();
}

String _checkin(LearnerHistoryCheckin c) => switch (c) {
      LearnerHistoryCheckin.passed => 'passed',
      LearnerHistoryCheckin.failed => 'failed',
      LearnerHistoryCheckin.notTaken => 'not taken',
    };
