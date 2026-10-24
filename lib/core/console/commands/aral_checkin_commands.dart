// lib/core/console/commands/aral_checkin_commands.dart

/// Commands for ARAL-Reading check-in assessments (local, offline-first; the
/// cut-off commands are online). One action per command; the ViewModel does
/// the checks. Learners are named by their ARAL enrollment id (the #id of
/// aral-roster); check-ins by the #id aral-checkins shows.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import '../../models/aral_checkin.dart';
import '../../models/aral_types.dart';
import 'aral_checkin_command_helpers.dart';

/// A YYYY-MM-DD token; one that isn't a real date is refused (F22).
bool _isDate(String a) {
  if (!looksLikeDateArg(a)) return false;
  if (strictDateArg(a) == null) throw AralCheckinUsage(notARealDateMessage(a));
  return true;
}

String _summary(AralCheckinResult r) {
  final c = r.checkin;
  final s = r.score;
  final state = r.complete ? '' : ' (${s.total - s.answered} not answered)';
  return '#${c.id} ${r.tool.label} attempt ${c.attemptNo} | ${c.takenOn} | ${s.correct}/${s.total} ${aralCheckinPct(s)} '
      '${aralCheckinVerdict(s, r.passPct)}$state${c.notes == null ? '' : ' | ${c.notes}'}';
}

void registerAralCheckinCommands(ConsoleRegistry registry, AralCheckinViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralCheckinUsage catch (e) {
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
    if (args.isEmpty) throw const AralCheckinUsage('Usage: aral-checkin-items <toolId>');
    final items = await vm.items(aralCheckinInt(args[0], 'toolId'));
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
    if (args.isEmpty) throw const AralCheckinUsage('Usage: aral-checkins <enrollmentId>');
    final l = await vm.learnerCheckins(aralCheckinInt(args[0], 'enrollmentId'));
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
    if (args.isEmpty) throw const AralCheckinUsage('Usage: aral-checkin <checkinId>');
    final r = await vm.result(aralCheckinInt(args[0], 'checkinId'));
    final lines = [_summary(r)];
    String? part;
    for (final i in r.items) {
      if (i.section != part) {
        part = i.section;
        if (part != null) {
          final s = r.scoring.sections[part]!;
          lines.add('$part: ${s.correct}/${s.total} ${aralCheckinPct(s)} ${aralCheckinVerdict(s, r.passPct)}');
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
    if (args.length < 2) throw const AralCheckinUsage(usage);
    var rest = args.sublist(2);
    DateTime? on;
    if (rest.isNotEmpty && _isDate(rest.first)) {
      on = DateTime.parse(rest.first);
      rest = rest.sublist(1);
    }
    final c = await vm.startCheckin(aralCheckinInt(args[0], 'enrollmentId'), aralCheckinInt(args[1], 'checkpoint'),
        on: on, notes: rest.isEmpty ? null : rest.join(' '));
    return 'Check-in #${c.id} recorded (attempt ${c.attemptNo}, ${c.takenOn}). '
        'Enter answers: aral-checkin-answers ${c.id} 1 <letters>; open items: aral-checkin-mark.';
  });

  add('aral-checkin-answers',
      'aral-checkin-answers <checkinId> <fromItemNo> <letters> — learner\'s letters for consecutive multiple-choice '
          'items (e.g. CDCA-B; "-" = left blank)', (args) async {
    const usage = 'Usage: aral-checkin-answers <checkinId> <fromItemNo> <letters> (e.g. CDCA-B)';
    if (args.length < 3) throw const AralCheckinUsage(usage);
    final letters = args.sublist(2).join().split('').map((ch) => ch == '-' ? null : ch).toList();
    final saved = await vm.answerChoices(aralCheckinInt(args[0], 'checkinId'), aralCheckinInt(args[1], 'fromItemNo'), letters);
    final right = saved.where((a) => a.isCorrect).length;
    return 'Saved ${saved.length} answer(s): $right right, ${saved.length - right} wrong.';
  });

  add('aral-checkin-mark',
      'aral-checkin-mark <checkinId> <itemNo> <right|wrong> ["what the learner wrote"] — mark an open item',
      (args) async {
    const usage = 'Usage: aral-checkin-mark <checkinId> <itemNo> <right|wrong> ["response"]';
    if (args.length < 3 || (args[2] != 'right' && args[2] != 'wrong')) throw const AralCheckinUsage(usage);
    final a = await vm.markOpen(aralCheckinInt(args[0], 'checkinId'), aralCheckinInt(args[1], 'itemNo'), args[2] == 'right',
        response: args.length > 3 ? args.sublist(3).join(' ') : null);
    return 'Item ${args[1]} marked ${a.isCorrect ? 'right' : 'wrong'}.';
  });

  add('aral-checkin-clear', 'aral-checkin-clear <checkinId> <itemNo> — remove an item\'s answer', (args) async {
    if (args.length < 2) throw const AralCheckinUsage('Usage: aral-checkin-clear <checkinId> <itemNo>');
    await vm.clearAnswer(aralCheckinInt(args[0], 'checkinId'), aralCheckinInt(args[1], 'itemNo'));
    return 'Item ${args[1]} is not answered now.';
  });

  add('aral-checkin-edit', 'aral-checkin-edit <checkinId> [YYYY-MM-DD] ["notes"|-] — change the date or notes',
      (args) async {
    const usage = 'Usage: aral-checkin-edit <checkinId> [YYYY-MM-DD] ["notes"|-]';
    if (args.length < 2) throw const AralCheckinUsage(usage);
    var rest = args.sublist(1);
    DateTime? on;
    if (_isDate(rest.first)) {
      on = DateTime.parse(rest.first);
      rest = rest.sublist(1);
    }
    final text = rest.join(' ');
    final c = await vm.editCheckin(aralCheckinInt(args[0], 'checkinId'),
        on: on, notes: rest.isEmpty ? null : (text == '-' ? '' : text));
    return 'Check-in #${c.id}: ${c.takenOn}${c.notes == null ? '' : ' | ${c.notes}'}.';
  });

  add('aral-checkin-delete', 'aral-checkin-delete <checkinId> — delete a check-in and its answers', (args) async {
    if (args.isEmpty) throw const AralCheckinUsage('Usage: aral-checkin-delete <checkinId>');
    await vm.deleteCheckin(aralCheckinInt(args[0], 'checkinId'));
    return 'Deleted check-in ${args[0]}.';
  });

  add('aral-checkin-cutoff','aral-checkin-cutoff [schoolId] — the check-in cut-off in the cloud (online)',
      (args) async {
    final schoolId = args.isEmpty ? null : aralCheckinInt(args[0], 'schoolId');
    final l = await vm.settingLayers(schoolId);
    String row(Object? v) => v == null ? '(not set)' : '$v%';
    return 'Default: ${l.defaults.passPct}%\n'
        'Region: ${row(l.region?.settings[AralCheckinSettings.passPctKey])}\n'
        '${schoolId == null ? '' : 'School $schoolId: ${row(l.school?.settings[AralCheckinSettings.passPctKey])}\n'}'
        'Applies: ${l.effective.passPct}%';
  });

  add('aral-sharp', 'aral-sharp [schoolId] — is the foundational literacy program (SHARP) on? (online)',
      (args) async {
    final schoolId = args.isEmpty ? null : aralCheckinInt(args[0], 'schoolId');
    final l = await vm.foundationalProgramLayers(schoolId);
    String row(bool? v) => v == null ? '(not set)' : (v ? 'on' : 'off');
    String said(bool v) => v ? 'on (levels 0-1 go to Foundational / SHARP)' : 'off (levels 0-1 go to KS1)';
    return 'Default: ${said(l.defaults)}\n'
        'Region: ${row(l.region)}\n'
        '${schoolId == null ? '' : 'School $schoolId: ${row(l.school)}\n'}'
        'Applies: ${said(l.effective)}';
  });

  add('aral-ks1-extended',
      'aral-ks1-extended [schoolId] — do KS1 Developing/Transitioning learners join ARAL (extended program)? (online)',
      (args) async {
    final schoolId = args.isEmpty ? null : aralCheckinInt(args[0], 'schoolId');
    final l = await vm.ks1ExtendedLayers(schoolId);
    String row(bool? v) => v == null ? '(not set)' : (v ? 'on' : 'off');
    String said(bool v) => v ? 'on (Developing/Transitioning join KS1 too)' : 'off (KS1 takes Low/High Emerging learners)';
    return 'Default: ${said(l.defaults)}\n'
        'Region: ${row(l.region)}\n'
        '${schoolId == null ? '' : 'School $schoolId: ${row(l.school)}\n'}'
        'Applies: ${said(l.effective)}';
  });

  add('aral-idle-days',
      'aral-idle-days [schoolId] — after how many days without a session a tutor is reminded (online)',
      (args) async {
    final schoolId = args.isEmpty ? null : aralCheckinInt(args[0], 'schoolId');
    final l = await vm.idleSessionDaysLayers(schoolId);
    String row(int? v) => v == null ? '(not set)' : '$v days';
    return 'Default: ${l.defaults} days\n'
        'Region: ${row(l.region)}\n'
        '${schoolId == null ? '' : 'School $schoolId: ${row(l.school)}\n'}'
        'Applies: ${l.effective} days';
  });
}
