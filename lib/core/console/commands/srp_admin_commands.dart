// lib/core/console/commands/srp_admin_commands.dart
// Admin build only: the admin half of srp_commands.dart (tutor build split, 2026-10-22).


import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../file_output.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show progressPercent;
import '../../../viewmodels/srp_viewmodel.dart';
import '../../services/srp_rules.dart';
import 'srp_command_helpers.dart';

void registerSrpAdminCommands(ConsoleRegistry registry, SrpViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on SrpUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('srp-list', 'srp-list <schoolId> <schoolYear> $_options — Summer Remediation Program candidates, '
      'weakest first', (args) async {
    if (args.length < 2) throw const SrpUsage('Usage: srp-list <schoolId> <schoolYear> $_options');
    final o = _filter(args.sublist(2));
    final list = await vm.candidates(
        schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    if (list.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _text(list, o.recommendedOnly);
  });

  add('srp-build', 'srp-build <schoolId> <schoolYear> [per=<n, default 15>] [size=<n, default 15>] '
      '[asof=YYYY-MM-DD] — build the SRP classes from the recommended learners (online)', (args) async {
    if (args.length < 2) throw const SrpUsage('Usage: srp-build <schoolId> <schoolYear> [per=n] [size=n] [asof=YYYY-MM-DD]');
    var per = srpDefaultPerSection, size = srpDefaultClassSize;
    DateTime? asOf;
    for (final o in args.sublist(2)) {
      final eq = o.indexOf('=');
      final raw = eq < 0 ? '' : o.substring(eq + 1).trim();
      switch (eq < 0 ? o : o.substring(0, eq)) {
        case 'per':
          per = srpInt(raw, 'per');
        case 'size':
          size = srpInt(raw, 'size');
        case 'asof':
          asOf = strictDateArg(raw) ?? (throw SrpUsage(asofDateMessage(raw)));
        default:
          throw SrpUsage('Unknown option "$o". Options: per=n size=n asof=YYYY-MM-DD');
      }
    }
    final classes = await vm.buildClasses(
        schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1], perSection: per, classSize: size, asOf: asOf);
    return _withWarning(vm, srpClassesText(classes, 'Built ${classes.length} SRP class(es):'));
  });

  add('srp-classes-csv', 'srp-classes-csv <schoolId> <schoolYear> <out.csv> — the SRP masterlist as CSV', (args) async {
    if (args.length != 3) throw const SrpUsage('Usage: srp-classes-csv <schoolId> <schoolYear> <out.csv>');
    final classes = await vm.classes(schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1]);
    final error = await writeOutputFile(args[2], text: srpClassesCsv(classes));
    if (error != null) return error;
    return 'Wrote ${outputPath(args[2])} (${classes.length} class(es), '
        '${classes.fold<int>(0, (n, c) => n + c.learners.length)} learner(s)).';
  });

  add('srp-class-set', 'srp-class-set <classId|name> [name=..] [room=..|-] [schedule=..|-] [tutor=<email>|-] — change a '
      'class (online; quote values with spaces: "schedule=MWF 8-10")', (args) async {
    if (args.length < 2) {
      throw const SrpUsage('Usage: srp-class-set <classId|name> [name=..] [room=..|-] [schedule=..|-] [tutor=<email>|-]');
    }
    String? name, room, schedule, tutor;
    var clearRoom = false, clearSchedule = false, clearTutor = false;
    for (final o in args.sublist(1)) {
      final eq = o.indexOf('=');
      if (eq < 0) throw SrpUsage('Options look like key=value (got "$o").');
      final raw = o.substring(eq + 1).trim();
      switch (o.substring(0, eq)) {
        case 'name':
          name = raw;
        case 'room':
          raw == '-' ? clearRoom = true : room = raw;
        case 'schedule':
          raw == '-' ? clearSchedule = true : schedule = raw;
        case 'tutor':
          raw == '-' ? clearTutor = true : tutor = raw;
        default:
          throw SrpUsage('Unknown option "${o.substring(0, eq)}". Options: name= room= schedule= tutor=');
      }
    }
    final c = await vm.updateClass(await vm.classIdFor(args[0]),
        className: name,
        room: room,
        schedule: schedule,
        tutorEmail: tutor,
        clearRoom: clearRoom,
        clearSchedule: clearSchedule,
        clearTutor: clearTutor);
    return _withWarning(vm, srpClassesText([c], 'Saved:'));
  });

  add('srp-add', 'srp-add <classId|name> <studentId> — put a learner in an SRP class (online)', (args) async {
    if (args.length != 2) throw const SrpUsage('Usage: srp-add <classId|name> <studentId>');
    final c = await vm.addLearner(await vm.classIdFor(args[0]), srpInt(args[1], 'studentId'));
    return _withWarning(vm, srpClassesText([c], 'Added:'));
  });

  add('srp-move', 'srp-move <studentId> <toClassId|name> — move a learner to another SRP class (online)', (args) async {
    if (args.length != 2) throw const SrpUsage('Usage: srp-move <studentId> <toClassId|name>');
    final c = await vm.moveLearner(srpInt(args[0], 'studentId'), await vm.classIdFor(args[1]));
    return _withWarning(vm, srpClassesText([c], 'Moved:'));
  });

  add('srp-remove', 'srp-remove <classId|name> <studentId> — take a learner out of an SRP class (online)', (args) async {
    if (args.length != 2) throw const SrpUsage('Usage: srp-remove <classId|name> <studentId>');
    final c = await vm.removeLearner(await vm.classIdFor(args[0]), srpInt(args[1], 'studentId'));
    return _withWarning(vm, srpClassesText([c], 'Removed:'));
  });

  add('srp-class-delete', 'srp-class-delete <classId|name> — delete an SRP class and take its learners out (online)',
      (args) async {
    if (args.length != 1) throw const SrpUsage('Usage: srp-class-delete <classId|name>');
    await vm.deleteClass(await vm.classIdFor(args[0]));
    return _withWarning(vm, 'Deleted SRP class ${args[0]}.');
  });

  add('srp-classes-clear', 'srp-classes-clear <schoolId> <schoolYear> yes — delete ALL the school\'s SRP classes '
      'for the year (online)', (args) async {
    if (args.length != 3 || args[2] != 'yes') {
      throw const SrpUsage('This deletes every SRP class of the school for that year. '
          'Usage: srp-classes-clear <schoolId> <schoolYear> yes');
    }
    final n = await vm.clearClasses(schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1]);
    return _withWarning(vm, 'Deleted $n SRP class(es).');
  });

  add('srp-list-csv','srp-list-csv <schoolId> <schoolYear> <out.csv> $_options — the same as CSV', (args) async {
    if (args.length < 3) throw const SrpUsage('Usage: srp-list-csv <schoolId> <schoolYear> <out.csv> $_options');
    final o = _filter(args.sublist(3));
    final list = await vm.candidates(
        schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    final error = await writeOutputFile(args[2], text: srpListCsv(list, recommendedOnly: o.recommendedOnly));
    if (error != null) return error;
    final n = list.sections.fold<int>(
        0, (n, s) => n + (o.recommendedOnly ? s.recommendedCount : s.candidates.length));
    return 'Wrote ${outputPath(args[2])} ($n learner(s)).';
  });
}

const _options = '[per=<n, default $srpDefaultPerSection>] [show=all|recommended] [sections=<id,...>] '
    '[asof=YYYY-MM-DD]';

({int per, bool recommendedOnly, Set<int>? sections, DateTime? asOf}) _filter(List<String> opts) {
  var per = srpDefaultPerSection;
  var recommendedOnly = false;
  Set<int>? sections;
  DateTime? asOf;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw SrpUsage('Options look like key=value (got "$o"). $_options');
    final key = o.substring(0, eq);
    final raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'per':
        per = srpInt(raw, 'per');
        if (per < 1) throw SrpUsage('per is at least 1 (got "$raw")');
      case 'show':
        final v = raw.toLowerCase();
        if (v != 'all' && v != 'recommended') throw SrpUsage('show is all or recommended (got "$raw")');
        recommendedOnly = v == 'recommended';
      case 'sections':
        sections = {
          for (final v in raw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)) srpInt(v, 'section id'),
        };
        if (sections.isEmpty) throw const SrpUsage('An option needs at least one value.');
      case 'asof':
        asOf = strictDateArg(raw) ?? (throw SrpUsage(asofDateMessage(raw)));
      default:
        throw SrpUsage('Unknown option "$key". $_options');
    }
  }
  return (per: per, recommendedOnly: recommendedOnly, sections: sections, asOf: asOf);
}

String _text(SrpList list, bool recommendedOnly) {
  final out = StringBuffer('SRP candidates (not grade level ready by EOSY) | school ${list.schoolId} '
      '| ${list.schoolYear} | as of ${list.asOf} | ${list.perSection} recommended per section');
  for (final s in list.sections) {
    out.write('\nG${s.grade} ${s.section.sectionName} (#${s.section.id}): ${s.candidates.length} of ${s.enrolled} '
        'not grade level ready, ${s.recommendedCount} recommended');
    for (final c in s.candidates) {
      if (recommendedOnly && !c.recommended) continue;
      final result = c.notAssessed
          ? 'NOT ASSESSED (assumed)'
          : 'comprehension ${progressPercent(c.key.comprehension)}%, words ${progressPercent(c.key.wordRecognition)}%, '
              '${c.key.speed.toStringAsFixed(0)} wpm (${c.basisRound!.label})';
      final down = c.levelsDown == null ? '' : ', ${c.levelsDown} down';
      out.write('\n  #${c.rank}${c.recommended ? ' *' : '  '} ${c.name} (${c.student.lrn}, ${c.student.sex ?? '?'})'
          ' · adjusted grade ${c.adjustedLevel}$down · ${c.profile.label} · $result');
    }
  }
  out.write('\n(* = recommended)');
  return out.toString();
}

String _withWarning(SrpViewModel vm, String text) =>
    vm.lastMirrorWarning == null ? text : '$text\nWARNING: ${vm.lastMirrorWarning}';
