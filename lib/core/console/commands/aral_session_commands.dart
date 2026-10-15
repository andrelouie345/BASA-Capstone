// lib/core/console/commands/aral_session_commands.dart

/// Commands for the ARAL-Reading session log and attendance (local,
/// offline-first). One action per command; the ViewModel does the checks.
/// Learners are named by their ARAL enrollment id (the #id of aral-roster).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_session_viewmodel.dart';
import '../../models/aral_session.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

final _setups = AralSetup.values.map((s) => s.value).join('|');

AralSetup? _setup(String raw) => AralSetup.values.where((s) => s.value == raw || s.name == raw).firstOrNull;

AralMark? _mark(String raw) => AralMark.values.where((m) => m.name == raw).firstOrNull;

bool _isDate(String a) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(a) && DateTime.tryParse(a) != null;

String _line(AralSession s) => '#${s.id} | session ${s.sessionNo} | ${s.heldOn} | ${s.minutes} min | ${s.setup.label} | '
    'tutor ${s.tutorId}${s.lesson == null ? '' : ' | ${s.lesson}'}${s.remarks == null ? '' : ' | remarks: ${s.remarks}'}';

/// Reads `lesson "<text>"` / `remarks "<text>"` pairs and the other options
/// out of [args]; unknown tokens are refused.
Map<String, String> _options(List<String> args, Set<String> flags, Set<String> valued, String usage) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (valued.contains(a)) {
      if (i + 1 >= args.length) throw _Usage('"$a" needs a value.\n$usage');
      out[a] = args[++i];
    } else if (_isDate(a)) {
      out['date'] = a;
    } else if (a.contains('=') && flags.contains(a.substring(0, a.indexOf('=')))) {
      out[a.substring(0, a.indexOf('='))] = a.substring(a.indexOf('=') + 1);
    } else {
      throw _Usage('Unknown option "$a".\n$usage');
    }
  }
  return out;
}

void registerAralSessionCommands(ConsoleRegistry registry, AralSessionViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          final out = await handler(args);
          final warning = vm.lastWarning;
          return warning == null ? out : '$out\nNote: $warning';
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-log',
      'aral-log <schoolYear> <minutes> <$_setups> [YYYY-MM-DD] [tutor=<userId>] [lesson "<text>"] '
          '[remarks "<text>"] — log an ARAL session (date defaults to today; a coordinator names the tutor)',
      (args) async {
    final usage = 'Usage: aral-log <schoolYear> <minutes> <$_setups> [YYYY-MM-DD] [tutor=<userId>] '
        '[lesson "<text>"] [remarks "<text>"]';
    if (args.length < 3) throw _Usage(usage);
    final setup = _setup(args[2]) ?? (throw _Usage('Unknown set-up "${args[2]}".\n$usage'));
    final o = _options(args.sublist(3), {'tutor'}, {'lesson', 'remarks'}, usage);
    vm.lastWarning = null;
    final s = await vm.logSession(
      schoolYear: args[0],
      minutes: _int(args[1], 'minutes'),
      setup: setup,
      heldOn: o['date'] == null ? null : DateTime.parse(o['date']!),
      tutorId: o['tutor'],
      lesson: o['lesson'],
      remarks: o['remarks'],
    );
    return 'Logged: ${_line(s)}\nMark attendance with aral-sheet ${s.id} / aral-mark / aral-mark-rest.';
  });

  add('aral-session-edit',
      'aral-session-edit <sessionId> [YYYY-MM-DD] [minutes=<n>] [setup=<$_setups>] [lesson "<text>"|"-"] '
          '[remarks "<text>"|"-"] — change a session ("-" clears the lesson or remarks)', (args) async {
    final usage = 'Usage: aral-session-edit <sessionId> [YYYY-MM-DD] [minutes=<n>] [setup=<setup>] '
        '[lesson "<text>"|"-"] [remarks "<text>"|"-"]';
    if (args.length < 2) throw _Usage(usage);
    final o = _options(args.sublist(1), {'minutes', 'setup'}, {'lesson', 'remarks'}, usage);
    String? Function()? text(String key) => o[key] == null ? null : () => o[key] == '-' ? null : o[key];
    vm.lastWarning = null;
    final s = await vm.editSession(
      _int(args[0], 'sessionId'),
      heldOn: o['date'] == null ? null : DateTime.parse(o['date']!),
      minutes: o['minutes'] == null ? null : _int(o['minutes']!, 'minutes'),
      setup: o['setup'] == null ? null : (_setup(o['setup']!) ?? (throw _Usage('Unknown set-up "${o['setup']}".'))),
      lesson: text('lesson'),
      remarks: text('remarks'),
    );
    return 'Updated: ${_line(s)}';
  });

  add('aral-session-delete', 'aral-session-delete <sessionId> — delete a session logged by mistake (and its marks)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-session-delete <sessionId>');
    vm.lastWarning = null;
    await vm.deleteSession(_int(args[0], 'sessionId'));
    return 'Deleted ARAL session ${args[0]}.';
  });

  add('aral-sessions',
      'aral-sessions [tutorId] [schoolYear] | aral-sessions school <schoolId> [schoolYear] — the session log '
          '(default: your own)', (args) async {
    vm.lastWarning = null;
    final List<AralSession> list;
    if (args.isNotEmpty && args[0] == 'school') {
      if (args.length < 2) throw const _Usage('Usage: aral-sessions school <schoolId> [schoolYear]');
      list = await vm.schoolSessions(schoolId: _int(args[1], 'schoolId'), schoolYear: args.elementAtOrNull(2));
    } else {
      final year = args.where((a) => RegExp(r'^\d{4}\s*-\s*\d{4}$').hasMatch(a)).firstOrNull;
      final tutor = args.where((a) => a != year).firstOrNull;
      list = await vm.tutorSessions(tutorId: tutor, schoolYear: year);
    }
    if (list.isEmpty) return 'No ARAL sessions.';
    final minutes = list.fold(0, (sum, s) => sum + s.minutes);
    return '${list.map(_line).join('\n')}\n${list.length} session(s), $minutes minutes.';
  });

  add('aral-sheet', 'aral-sheet <sessionId> — the session\'s attendance sheet (the tutor\'s learners on that date)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-sheet <sessionId>');
    vm.lastWarning = null;
    final id = _int(args[0], 'sessionId');
    final s = await vm.getSession(id);
    final lines = await vm.sheet(id);
    if (lines.isEmpty) return '${_line(s)}\nNobody on the sheet (the tutor has no ARAL learners on ${s.heldOn}).';
    final names = await vm.learnerNames(lines.map((l) => l.enrollment));
    final rows = [
      for (final l in lines)
        '#${l.enrollment.id} | ${names[l.enrollment.studentId] ?? 'student ${l.enrollment.studentId}'} | '
            '${l.enrollment.programLabel} | ${l.attendance?.mark.name ?? '(not marked)'}'
            '${l.attendance?.note == null ? '' : ' - ${l.attendance!.note}'}${l.expected ? '' : ' | from another group'}',
    ];
    final unmarked = lines.where((l) => l.attendance == null).length;
    return '${_line(s)}\n${rows.join('\n')}\n${lines.length} learner(s), $unmarked not marked.';
  });

  add('aral-mark',
      'aral-mark <sessionId> <enrollmentId> <present|absent|excused> ["note"] — mark one learner (again = replace)',
      (args) async {
    const usage = 'Usage: aral-mark <sessionId> <enrollmentId> <present|absent|excused> ["note"]';
    if (args.length < 3) throw const _Usage(usage);
    final mark = _mark(args[2]) ?? (throw const _Usage(usage));
    vm.lastWarning = null;
    final a = await vm.mark(_int(args[0], 'sessionId'), _int(args[1], 'enrollmentId'), mark,
        note: args.length > 3 ? args.sublist(3).join(' ') : null);
    return 'Marked #${a.enrollmentId} ${a.mark.name}${a.note == null ? '' : ' (${a.note})'}.';
  });

  add('aral-mark-rest',
      'aral-mark-rest <sessionId> <present|absent|excused> — give everyone on the sheet without a mark this mark',
      (args) async {
    const usage = 'Usage: aral-mark-rest <sessionId> <present|absent|excused>';
    if (args.length < 2) throw const _Usage(usage);
    final mark = _mark(args[1]) ?? (throw const _Usage(usage));
    vm.lastWarning = null;
    final written = await vm.markRest(_int(args[0], 'sessionId'), mark);
    return written.isEmpty ? 'Everyone on the sheet is already marked.' : 'Marked ${written.length} learner(s) ${mark.name}.';
  });

  add('aral-unmark', 'aral-unmark <sessionId> <enrollmentId> — remove a learner\'s mark', (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-unmark <sessionId> <enrollmentId>');
    vm.lastWarning = null;
    await vm.unmark(_int(args[0], 'sessionId'), _int(args[1], 'enrollmentId'));
    return 'Mark removed.';
  });

  add('aral-attendance', 'aral-attendance <enrollmentId> — one ARAL learner\'s attendance for the year',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-attendance <enrollmentId>');
    vm.lastWarning = null;
    final (summary, rows) = await vm.learnerAttendance(_int(args[0], 'enrollmentId'));
    if (rows.isEmpty) return 'No marks yet.';
    final lines = rows.map((r) => 'session ${r.$1.sessionNo} | ${r.$1.heldOn} | tutor ${r.$1.tutorId} | ${r.$2.mark.name}'
        '${r.$2.note == null ? '' : ' - ${r.$2.note}'}');
    return '${lines.join('\n')}\n${summary.label}';
  });

  add('aral-tutor-summary',
      'aral-tutor-summary <schoolYear> [tutorId] — sessions, minutes, next check-in and attendance (default: you)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-tutor-summary <schoolYear> [tutorId]');
    vm.lastWarning = null;
    final t = await vm.tutorSummary(schoolYear: args[0], tutorId: args.elementAtOrNull(1));
    final next = t.nextCheckInAfter == null
        ? 'both check-ins are past'
        : 'next check-in after session ${t.nextCheckInAfter} (${t.nextCheckInAfter! - (t.lastSessionNo ?? 0)} to go)';
    return '${t.tutor.fullName} (${t.tutor.id}): ${t.sessions} session(s), ${t.totalMinutes} minutes, '
        'last session ${t.lastSessionNo ?? '-'}; $next\n'
        '${t.activeLearners} active ARAL learner(s); marks: ${t.attendance.label}\n'
        'Sessions per day: ${t.multipleSessionsPerDay ? 'several allowed' : 'one'}';
  });

  add('aral-tutor-multi',
      'aral-tutor-multi <tutorId> [on|off] — allow (on) or stop allowing (off) a tutor several ARAL sessions on '
          'one date; without on/off shows the current setting (default: one per day)', (args) async {
    const usage = 'Usage: aral-tutor-multi <tutorId> [on|off]';
    if (args.isEmpty) throw const _Usage(usage);
    vm.lastWarning = null;
    if (args.length == 1) {
      final allowed = await vm.allowsMultipleSessionsPerDay(args[0]);
      return 'Tutor ${args[0]}: ${allowed ? 'several sessions per day allowed' : 'one session per day'}.';
    }
    final allowed = switch (args[1]) {
      'on' => true,
      'off' => false,
      _ => throw const _Usage(usage),
    };
    final s = await vm.setMultipleSessionsPerDay(args[0], allowed);
    return 'Tutor ${s.tutorId}: ${s.multipleSessionsPerDay ? 'several sessions per day allowed' : 'one session per day'}'
        '${allowed ? '' : ' (sessions already on the same date stay)'}.';
  });
}
