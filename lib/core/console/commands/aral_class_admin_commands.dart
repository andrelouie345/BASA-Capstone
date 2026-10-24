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

  final programs = '${AralClassProgram.values.map((p) => p.value).join('|')}|mixed';
  // null = mixed programs.
  AralClassProgram? program(String raw) => raw == 'mixed'
      ? null
      : AralClassProgram.values.firstWhere((p) => p.value == raw,
          orElse: () => throw AralUsage('Unknown program "$raw" (expected $programs)'));
  int grade(String raw) => aralInt(raw, 'grade');

  final addUsage = 'Usage: aral-class-add <schoolId> <schoolYear> <grade 1-10> <$programs> <name...> [tutor=<userId>] '
      '["room=<room>"] ["schedule=<when>"] ["notes=<text>"]';
  add('aral-class-add',
      'aral-class-add <schoolId> <schoolYear> <grade 1-10> <program|mixed> <name...> [tutor=<userId>] ["room=.."] '
          '["schedule=.."] ["notes=.."] — a new ARAL class of one grade, with one program or mixed programs '
          '(program $programs)', (args) async {
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
      gradeLevel: grade(args[2]),
      program: program(args[3]),
      className: words.join(' '),
      tutorId: opts['tutor'],
      room: opts['room'],
      schedule: opts['schedule'],
      notes: opts['notes'],
    );
    return 'ARAL class added: ${aralClassLine(c, cap: vm.classCap, active: 0)}';
  });

  const editUsage = 'Usage: aral-class-edit <classId> <name|tutor|room|schedule|notes|grade|program> <value...> '
      '("-" clears tutor, room, schedule or notes; program mixed = mixed programs)';
  add('aral-class-edit',
      'aral-class-edit <classId> <name|tutor|room|schedule|notes|grade|program> <value...> — change one thing about '
          'an ARAL class ("-" clears tutor, room, schedule or notes; program mixed = mixed programs)', (args) async {
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
      'grade' => current.copyWith(gradeLevel: grade(value)),
      'program' => current.copyWith(program: () => program(value)),
      _ => throw const AralUsage(editUsage),
    };
    final saved = await vm.editClass(changed);
    return 'ARAL class saved: ${aralClassLine(saved, cap: vm.classCap, active: await vm.activeCount(saved.id!))}';
  });

  const placeUsage = 'Usage: aral-class-place <enrollmentId> <classId> [other-grade]';
  add('aral-class-place',
      'aral-class-place <enrollmentId> <classId> [other-grade] — put an ARAL learner in a class, or move them to '
          'another one (other-grade = place a learner of another grade than the class\'s)', (args) async {
    if (args.length < 2 || args.length > 3 || (args.length == 3 && args[2] != 'other-grade')) {
      throw const AralUsage(placeUsage);
    }
    final e = await vm.place(aralInt(args[0], 'enrollmentId'), aralInt(args[1], 'classId'),
        otherGrade: args.length == 3);
    final c = await vm.getClass(e.classId!);
    return 'ARAL learner #${e.id} placed in ${aralClassLine(c, cap: vm.classCap, active: await vm.activeCount(c.id!))}';
  });

  add('aral-class-unplace', 'aral-class-unplace <enrollmentId> — take an ARAL learner out of their class',
      (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-class-unplace <enrollmentId>');
    final e = await vm.unplace(aralInt(args[0], 'enrollmentId'));
    return 'ARAL learner #${e.id} now waits for a class.';
  });

  add('aral-class-delete', 'aral-class-delete <classId> — delete an ARAL class', (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-class-delete <classId>');
    final id = aralInt(args[0], 'classId');
    final c = await vm.getClass(id);
    await vm.deleteClass(id);
    return 'ARAL class #$id "${c.className}" deleted.';
  });
}
