// lib/core/console/commands/aral_checkin_admin_commands.dart
// Admin build only: the admin half of aral_checkin_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import 'aral_checkin_command_helpers.dart';

void registerAralCheckinAdminCommands(ConsoleRegistry registry, AralCheckinViewModel vm) {
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

  add('aral-checkin-report',
      'aral-checkin-report <schoolId> <schoolYear> [sectionId] — each ARAL learner\'s latest check-in after '
          'sessions 16 and 32, with per-section totals (admin/coordinator)', (args) async {
    const usage = 'Usage: aral-checkin-report <schoolId> <schoolYear> [sectionId]';
    if (args.length < 2) throw const AralCheckinUsage(usage);
    final r = await vm.checkinReport(
        schoolId: aralCheckinInt(args[0], 'schoolId'),
        schoolYear: args[1],
        sectionId: args.length > 2 ? aralCheckinInt(args[2], 'sectionId') : null);
    if (r.sections.isEmpty) return 'No ARAL learners in school ${r.schoolId} for ${r.schoolYear}.';
    String cell(AralCheckinResult? x) {
      if (x == null) return 'not taken';
      final s = x.score;
      return '${s.correct}/${s.total} ${aralCheckinPct(s)} ${aralCheckinVerdict(s, r.passPct)}'
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

  add('aral-checkin-cutoff-set',
      'aral-checkin-cutoff-set <region|schoolId> <1-100> — set the check-in cut-off (online)', (args) async {
    const usage = 'Usage: aral-checkin-cutoff-set <region|schoolId> <1-100>';
    if (args.length < 2) throw const AralCheckinUsage(usage);
    final schoolId = args[0] == 'region' ? null : aralCheckinInt(args[0], 'schoolId');
    await vm.setPassPct(schoolId, aralCheckinInt(args[1], 'cut-off'));
    final warn = vm.lastMirrorWarning;
    return 'Cut-off for ${schoolId == null ? 'the region' : 'school $schoolId'} set to ${args[1]}%.'
        '${warn == null ? '' : '\n$warn'}';
  });

  add('aral-sharp-set',
      'aral-sharp-set <region|schoolId> <on|off> — switch the foundational literacy program (SHARP) (online)',
      (args) async {
    const usage = 'Usage: aral-sharp-set <region|schoolId> <on|off>';
    if (args.length != 2 || (args[1] != 'on' && args[1] != 'off')) throw const AralCheckinUsage(usage);
    final schoolId = args[0] == 'region' ? null : aralCheckinInt(args[0], 'schoolId');
    await vm.setFoundationalProgram(schoolId, args[1] == 'on');
    final warn = vm.lastMirrorWarning;
    return 'Foundational literacy program (SHARP) ${args[1]} for '
        '${schoolId == null ? 'the region' : 'school $schoolId'}. Learners already in ARAL move at the next '
        'aral-update.${warn == null ? '' : '\n$warn'}';
  });

  add('aral-checkin-cutoff-reset',
      'aral-checkin-cutoff-reset <schoolId> — remove a school\'s ARAL settings override: cut-off, SHARP switch, '
          'idle session days (online)', (args) async {
    if (args.isEmpty) throw const AralCheckinUsage('Usage: aral-checkin-cutoff-reset <schoolId>');
    final schoolId = aralCheckinInt(args[0], 'schoolId');
    await vm.resetSchoolSettings(schoolId);
    final warn = vm.lastMirrorWarning;
    return 'School $schoolId uses the region ARAL settings again (cut-off, SHARP, idle session days).'
        '${warn == null ? '' : '\n$warn'}';
  });

  add('aral-idle-days-set',
      'aral-idle-days-set <region|schoolId> <1-60> — set the "no session lately" reminder\'s days (online)',
      (args) async {
    const usage = 'Usage: aral-idle-days-set <region|schoolId> <1-60>';
    if (args.length != 2) throw const AralCheckinUsage(usage);
    final schoolId = args[0] == 'region' ? null : aralCheckinInt(args[0], 'schoolId');
    await vm.setIdleSessionDays(schoolId, aralCheckinInt(args[1], 'days'));
    final warn = vm.lastMirrorWarning;
    return 'Idle session days for ${schoolId == null ? 'the region' : 'school $schoolId'} set to ${args[1]}.'
        '${warn == null ? '' : '\n$warn'}';
  });
}
