// lib/core/console/commands/aral_class_admin_commands.dart
// Admin build only: create, change and delete ARAL classes.

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_class_viewmodel.dart';
import '../../models/aral_class.dart';
import 'aral_command_helpers.dart';

void registerAralClassAdminCommands(ConsoleRegistry registry, AralClassViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  final programs = AralClassProgram.values.map((p) => p.value).join('|');
  final bands = AralGradeBand.values.map((b) => b.value).join('|');
  AralClassProgram program(String raw) => AralClassProgram.values.firstWhere((p) => p.value == raw,
      orElse: () => throw AralUsage('Unknown program "$raw" (expected $programs)'));
  AralGradeBand band(String raw) => AralGradeBand.values.firstWhere((b) => b.value == raw,
      orElse: () => throw AralUsage('Unknown grade band "$raw" (expected $bands)'));

  final addUsage = 'Usage: aral-class-add <schoolId> <schoolYear> <$programs> <$bands> <name...> [tutor=<userId>] '
      '["room=<room>"] ["schedule=<when>"] ["notes=<text>"]';
  add('aral-class-add',
      'aral-class-add <schoolId> <schoolYear> <program> <band> <name...> [tutor=<userId>] ["room=.."] ["schedule=.."] '
          '["notes=.."] — a new ARAL class (program $programs; band $bands)', (args) async {
    if (args.length < 5) throw AralUsage(addUsage);
    final words = <String>[];
    final opts = <String, String>{};
    for (final a in args.skip(4)) {
      final eq = a.indexOf('=');
      final key = eq > 0 ? a.substring(0, eq) : null;
      if (key != null && const {'tutor', 'room', 'schedule', 'notes'}.contains(key)) {
        opts[key] = a.substring(eq + 1);
      } else {
        words.add(a);
      }
    }
    if (words.isEmpty) throw AralUsage(addUsage);
    final c = await vm.createClass(
      schoolId: aralInt(args[0], 'schoolId'),
      schoolYear: args[1],
      program: program(args[2]),
      gradeBand: band(args[3]),
      className: words.join(' '),
      tutorId: opts['tutor'],
      room: opts['room'],
      schedule: opts['schedule'],
      notes: opts['notes'],
    );
    return 'ARAL class added: ${aralClassLine(c)}';
  });

  const editUsage = 'Usage: aral-class-edit <classId> <name|tutor|room|schedule|notes|program|band> <value...> '
      '("-" clears tutor, room, schedule or notes)';
  add('aral-class-edit',
      'aral-class-edit <classId> <name|tutor|room|schedule|notes|program|band> <value...> — change one thing about an '
          'ARAL class ("-" clears tutor, room, schedule or notes)', (args) async {
    if (args.length < 3) throw const AralUsage(editUsage);
    final current = await vm.getClass(aralInt(args[0], 'classId'));
    final value = args.skip(2).join(' ');
    String? orNull() => value == '-' ? null : value;
    final changed = switch (args[1]) {
      'name' => current.copyWith(className: value),
      'tutor' => current.copyWith(tutorId: orNull),
      'room' => current.copyWith(room: orNull),
      'schedule' => current.copyWith(schedule: orNull),
      'notes' => current.copyWith(notes: orNull),
      'program' => current.copyWith(program: program(value)),
      'band' => current.copyWith(gradeBand: band(value)),
      _ => throw const AralUsage(editUsage),
    };
    return 'ARAL class saved: ${aralClassLine(await vm.editClass(changed))}';
  });

  add('aral-class-delete', 'aral-class-delete <classId> — delete an ARAL class', (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-class-delete <classId>');
    final id = aralInt(args[0], 'classId');
    final c = await vm.getClass(id);
    await vm.deleteClass(id);
    return 'ARAL class #$id "${c.className}" deleted.';
  });
}
