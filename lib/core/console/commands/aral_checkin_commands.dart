// lib/core/console/commands/aral_checkin_commands.dart

/// Commands for ARAL-Reading check-in assessments (local, offline-first; the
/// cut-off commands are online). One action per command; the ViewModel does
/// the checks. Learners are named by their ARAL enrollment id (the #id of
/// aral-roster); check-ins by the #id aral-checkins shows.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import '../../models/aral_checkin.dart';
import '../../services/aral_checkin_rules.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

bool _isDate(String a) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(a) && DateTime.tryParse(a) != null;

String _pct(AralCheckinScore s) => '${s.percent.toStringAsFixed(0)}%';

String _verdict(AralCheckinScore s, int passPct) => s.passes(passPct) ? 'Met' : 'Not met';

String _summary(AralCheckinResult r) {
  final c = r.checkin;
  final s = r.score;
  final state = r.complete ? '' : ' (${s.total - s.answered} not answered)';
  return '#${c.id} ${r.tool.label} attempt ${c.attemptNo} | ${c.takenOn} | ${s.correct}/${s.total} ${_pct(s)} '
      '${_verdict(s, r.passPct)}$state${c.notes == null ? '' : ' | ${c.notes}'}';
}

void registerAralCheckinCommands(ConsoleRegistry registry, AralCheckinViewModel vm) {
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

  add('aral-checkin-tools', 'aral-checkin-tools — the check-in tools on this device (with tool ids)', (args) async {
    final tools = await vm.tools();
    if (tools.isEmpty) return 'No check-in tools locally (pull-cloud brings them).';
    final lines = <String>[];
    for (final t in tools) {
      final items = await vm.items(t.id);
      final open = items.where((i) => i.kind == AralCheckinItemKind.open).length;
      lines.add('#${t.id} ${t.label} | ${t.language} | ${items.length} items${open == 0 ? '' : ' ($open marked by the tutor)'}');
    }
    return lines.join('\n');
  });

  add('aral-checkin-items', 'aral-checkin-items <toolId> — a tool\'s items, parts and keys', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-checkin-items <toolId>');
    final items = await vm.items(_int(args[0], 'toolId'));
    if (items.isEmpty) return 'No items for tool ${args[0]}.';
    final lines = <String>[];
    String? part;
    for (final i in items) {
      if (i.section != part) {
        part = i.section;
        if (part != null) lines.add(part);
      }
      final key = i.kind == AralCheckinItemKind.choice ? 'key ${i.answerKey}' : 'open: ${i.answerKey ?? '(own answer)'}';
      lines.add('  ${i.itemNo}${i.label == null ? '' : ' [${i.label}]'}. ${i.prompt} | $key');
    }
    return lines.join('\n');
  });

  add('aral-checkins', 'aral-checkins <enrollmentId> — a learner\'s check-ins with scores (today\'s cut-off)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-checkins <enrollmentId>');
    final l = await vm.learnerCheckins(_int(args[0], 'enrollmentId'));
    final e = l.enrollment;
    final lines = ['ARAL #${e.id} (student ${e.studentId}) | ${e.programLabel}'];
    if (l.toolsByCheckpoint.isEmpty) {
      lines.add('No check-in tools for ${e.programLabel}.');
    } else {
      lines.add('Tools: ${l.toolsByCheckpoint.entries.map((t) => 'after session ${t.key} = #${t.value.id}').join(', ')}');
    }
    if (l.results.isEmpty) {
      lines.add('No check-ins yet.');
    } else {
      lines.addAll(l.results.map(_summary));
      lines.add('Cut-off: ${l.results.first.passPct}%');
    }
    return lines.join('\n');
  });

  add('aral-checkin', 'aral-checkin <checkinId> — one check-in: every item, the score per part, met or not',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-checkin <checkinId>');
    final r = await vm.result(_int(args[0], 'checkinId'));
    final lines = [_summary(r)];
    String? part;
    for (final i in r.items) {
      if (i.section != part) {
        part = i.section;
        if (part != null) {
          final s = r.scoring.sections[part]!;
          lines.add('$part: ${s.correct}/${s.total} ${_pct(s)} ${_verdict(s, r.passPct)}');
        }
      }
      final a = r.answerByItem[i.id];
      final mark = a == null ? '-' : (a.isCorrect ? 'right' : 'wrong');
      final given = a?.response == null ? '' : ' "${a!.response}"';
      lines.add('  ${i.displayNo}. $mark$given${i.kind == AralCheckinItemKind.choice ? ' (key ${i.answerKey})' : ''}');
    }
    lines.add('Cut-off: ${r.passPct}%');
    return lines.join('\n');
  });

  add('aral-checkin-start',
      'aral-checkin-start <enrollmentId> <16|32> [YYYY-MM-DD] ["notes"] — record a check-in attempt '
          '(date defaults to today)', (args) async {
    const usage = 'Usage: aral-checkin-start <enrollmentId> <16|32> [YYYY-MM-DD] ["notes"]';
    if (args.length < 2) throw const _Usage(usage);
    var rest = args.sublist(2);
    DateTime? on;
    if (rest.isNotEmpty && _isDate(rest.first)) {
      on = DateTime.parse(rest.first);
      rest = rest.sublist(1);
    }
    final c = await vm.startCheckin(_int(args[0], 'enrollmentId'), _int(args[1], 'checkpoint'),
        on: on, notes: rest.isEmpty ? null : rest.join(' '));
    return 'Check-in #${c.id} recorded (attempt ${c.attemptNo}, ${c.takenOn}). '
        'Enter answers: aral-checkin-answers ${c.id} 1 <letters>; open items: aral-checkin-mark.';
  });

  add('aral-checkin-answers',
      'aral-checkin-answers <checkinId> <fromItemNo> <letters> — learner\'s letters for consecutive multiple-choice '
          'items (e.g. CDCA-B; "-" = left blank)', (args) async {
    const usage = 'Usage: aral-checkin-answers <checkinId> <fromItemNo> <letters> (e.g. CDCA-B)';
    if (args.length < 3) throw const _Usage(usage);
    final letters = args.sublist(2).join().split('').map((ch) => ch == '-' ? null : ch).toList();
    final saved = await vm.answerChoices(_int(args[0], 'checkinId'), _int(args[1], 'fromItemNo'), letters);
    final right = saved.where((a) => a.isCorrect).length;
    return 'Saved ${saved.length} answer(s): $right right, ${saved.length - right} wrong.';
  });

  add('aral-checkin-mark',
      'aral-checkin-mark <checkinId> <itemNo> <right|wrong> ["what the learner wrote"] — mark an open item',
      (args) async {
    const usage = 'Usage: aral-checkin-mark <checkinId> <itemNo> <right|wrong> ["response"]';
    if (args.length < 3 || (args[2] != 'right' && args[2] != 'wrong')) throw const _Usage(usage);
    final a = await vm.markOpen(_int(args[0], 'checkinId'), _int(args[1], 'itemNo'), args[2] == 'right',
        response: args.length > 3 ? args.sublist(3).join(' ') : null);
    return 'Item ${args[1]} marked ${a.isCorrect ? 'right' : 'wrong'}.';
  });

  add('aral-checkin-clear', 'aral-checkin-clear <checkinId> <itemNo> — remove an item\'s answer', (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-checkin-clear <checkinId> <itemNo>');
    await vm.clearAnswer(_int(args[0], 'checkinId'), _int(args[1], 'itemNo'));
    return 'Item ${args[1]} is not answered now.';
  });

  add('aral-checkin-edit', 'aral-checkin-edit <checkinId> [YYYY-MM-DD] ["notes"|-] — change the date or notes',
      (args) async {
    const usage = 'Usage: aral-checkin-edit <checkinId> [YYYY-MM-DD] ["notes"|-]';
    if (args.length < 2) throw const _Usage(usage);
    var rest = args.sublist(1);
    DateTime? on;
    if (_isDate(rest.first)) {
      on = DateTime.parse(rest.first);
      rest = rest.sublist(1);
    }
    final text = rest.join(' ');
    final c = await vm.editCheckin(_int(args[0], 'checkinId'),
        on: on, notes: rest.isEmpty ? null : (text == '-' ? '' : text));
    return 'Check-in #${c.id}: ${c.takenOn}${c.notes == null ? '' : ' | ${c.notes}'}.';
  });

  add('aral-checkin-delete', 'aral-checkin-delete <checkinId> — delete a check-in and its answers', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-checkin-delete <checkinId>');
    await vm.deleteCheckin(_int(args[0], 'checkinId'));
    return 'Deleted check-in ${args[0]}.';
  });

  add('aral-checkin-report',
      'aral-checkin-report <schoolId> <schoolYear> [sectionId] — each ARAL learner\'s latest check-in after '
          'sessions 16 and 32, with per-section totals (admin/coordinator)', (args) async {
    const usage = 'Usage: aral-checkin-report <schoolId> <schoolYear> [sectionId]';
    if (args.length < 2) throw const _Usage(usage);
    final r = await vm.checkinReport(
        schoolId: _int(args[0], 'schoolId'),
        schoolYear: args[1],
        sectionId: args.length > 2 ? _int(args[2], 'sectionId') : null);
    if (r.sections.isEmpty) return 'No ARAL learners in school ${r.schoolId} for ${r.schoolYear}.';
    String cell(AralCheckinResult? x) {
      if (x == null) return 'not taken';
      final s = x.score;
      return '${s.correct}/${s.total} ${_pct(s)} ${_verdict(s, r.passPct)}'
          '${x.complete ? '' : ' (incomplete)'}${x.checkin.attemptNo > 1 ? ' [attempt ${x.checkin.attemptNo}]' : ''}';
    }

    final lines = ['ARAL check-ins, school ${r.schoolId}, ${r.schoolYear} (cut-off ${r.passPct}%)'];
    for (final s in r.sections) {
      lines.add('Grade ${s.section.gradeLevel} ${s.section.sectionName} (section ${s.section.id}):');
      for (final l in s.learners) {
        final e = l.enrollment;
        final head = '  #${e.id} ${l.name} | ${e.programLabel}${e.isActive ? '' : ' (exited)'}';
        lines.add(l.hasTools
            ? '$head | after 16: ${cell(l.after16)} | after 32: ${cell(l.after32)}'
            : '$head | no check-in tools');
      }
      lines.add('  Totals (${s.withTools} with check-in tools): after 16 took ${s.took(16)}, met ${s.met(16)} | '
          'after 32 took ${s.took(32)}, met ${s.met(32)}');
    }
    if (r.sections.length > 1) {
      lines.add('School: after 16 took ${r.took(16)}, met ${r.met(16)} | after 32 took ${r.took(32)}, met ${r.met(32)}');
    }
    return lines.join('\n');
  });

  add('aral-checkin-cutoff','aral-checkin-cutoff [schoolId] — the check-in cut-off in the cloud (online)',
      (args) async {
    final schoolId = args.isEmpty ? null : _int(args[0], 'schoolId');
    final l = await vm.settingLayers(schoolId);
    String row(Object? v) => v == null ? '(not set)' : '$v%';
    return 'Default: ${AralCheckinSettings.defaults.passPct}%\n'
        'Region: ${row(l.region?.settings[AralCheckinSettings.passPctKey])}\n'
        '${schoolId == null ? '' : 'School $schoolId: ${row(l.school?.settings[AralCheckinSettings.passPctKey])}\n'}'
        'Applies: ${l.effective.passPct}%';
  });

  add('aral-checkin-cutoff-set',
      'aral-checkin-cutoff-set <region|schoolId> <1-100> — set the check-in cut-off (online)', (args) async {
    const usage = 'Usage: aral-checkin-cutoff-set <region|schoolId> <1-100>';
    if (args.length < 2) throw const _Usage(usage);
    final schoolId = args[0] == 'region' ? null : _int(args[0], 'schoolId');
    await vm.setPassPct(schoolId, _int(args[1], 'cut-off'));
    final warn = vm.lastMirrorWarning;
    return 'Cut-off for ${schoolId == null ? 'the region' : 'school $schoolId'} set to ${args[1]}%.'
        '${warn == null ? '' : '\n$warn'}';
  });

  add('aral-checkin-cutoff-reset', 'aral-checkin-cutoff-reset <schoolId> — remove a school\'s cut-off (online)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-checkin-cutoff-reset <schoolId>');
    final schoolId = _int(args[0], 'schoolId');
    await vm.resetSchoolSettings(schoolId);
    final warn = vm.lastMirrorWarning;
    return 'School $schoolId uses the region cut-off again.${warn == null ? '' : '\n$warn'}';
  });
}
