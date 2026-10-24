// lib/core/console/commands/aral_commands.dart

/// Commands for the ARAL-Reading roster (local, offline-first): BASA's
/// proposal, putting learners on the roster, their program, class, exit and
/// notes. One action per command; the ViewModel does the checks.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import '../../models/aral_enrollment.dart';
import 'aral_command_helpers.dart';

void registerAralCommands(ConsoleRegistry registry, AralViewModel vm) {
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

  add('aral-roster',
      'aral-roster <sectionId> [schoolYear] | aral-roster school <schoolId> [schoolYear] | '
          'aral-roster tutor [userId] [schoolYear] — the ARAL roster', (args) async {
    const usage = 'Usage: aral-roster <sectionId> [schoolYear] | school <schoolId> [schoolYear] | tutor [userId] [schoolYear]';
    if (args.isEmpty) throw const AralUsage(usage);
    List<AralEnrollment> list;
    if (args[0] == 'school') {
      if (args.length < 2) throw const AralUsage(usage);
      list = await vm.schoolRoster(schoolId: aralInt(args[1], 'schoolId'), schoolYear: args.elementAtOrNull(2));
    } else if (args[0] == 'tutor') {
      final rest = args.skip(1).toList();
      final year = rest.where((a) => RegExp(r'^\d{4}\s*-\s*\d{4}$').hasMatch(a)).firstOrNull;
      final id = rest.where((a) => a != year).firstOrNull;
      list = await vm.tutorRoster(tutorId: id, schoolYear: year);
    } else {
      list = await vm.roster(sectionId: aralInt(args[0], 'sectionId'), schoolYear: args.elementAtOrNull(1));
    }
    if (list.isEmpty) return 'Nobody on that ARAL roster.';
    final names = <int, String>{};
    for (final section in list.map((e) => e.sectionId).toSet()) {
      names.addAll(await vm.learnerNames(section));
    }
    final classes = await vm.classNames(list.first.schoolId);
    final active = list.where((e) => e.isActive).length;
    final waiting = list.where((e) => e.isActive && e.classId == null).length;
    return '${list.map((e) => aralLine(e, names, classes)).join('\n')}\n'
        '${list.length} on the roster, $active active, $waiting waiting for a class.';
  });

  add('aral-tutors', 'aral-tutors <schoolId> <schoolYear> — the school\'s tutors, with their ARAL classes and learners',
      (args) async {
    if (args.length < 2) throw const AralUsage('Usage: aral-tutors <schoolId> <schoolYear>');
    final list = await vm.tutors(schoolId: aralInt(args[0], 'schoolId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No active tutors in that school.';
    return list
        .map((t) => '${t.tutor.id} | ${t.tutor.fullName} | ${t.classes} class(es), ${t.activeLearners} active ARAL learner(s)')
        .join('\n');
  });
}
