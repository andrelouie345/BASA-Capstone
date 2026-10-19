// lib/core/console/commands/srp_commands.dart

/// Summer Remediation Program (SRP), part 1: learners not grade level ready by
/// the end of the year, ranked weakest first, the weakest per section
/// recommended. Options:
///   per=N                  recommended learners per section (default 15)
///   show=all|recommended   every candidate, or only the recommended (default all)
///   sections=ID,...        only these sections (default: every Grade 4-10 section)
///   asof=YYYY-MM-DD        results assessed by that date (default today)
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show progressPercent;
import '../../../viewmodels/srp_viewmodel.dart';
import '../../services/srp_rules.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

const _options = '[per=<n, default $srpDefaultPerSection>] [show=all|recommended] [sections=<id,...>] '
    '[asof=YYYY-MM-DD]';

({int per, bool recommendedOnly, Set<int>? sections, DateTime? asOf}) _filter(List<String> opts) {
  var per = srpDefaultPerSection;
  var recommendedOnly = false;
  Set<int>? sections;
  DateTime? asOf;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_options');
    final key = o.substring(0, eq);
    final raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'per':
        per = _int(raw, 'per');
        if (per < 1) throw _Usage('per is at least 1 (got "$raw")');
      case 'show':
        final v = raw.toLowerCase();
        if (v != 'all' && v != 'recommended') throw _Usage('show is all or recommended (got "$raw")');
        recommendedOnly = v == 'recommended';
      case 'sections':
        sections = {
          for (final v in raw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)) _int(v, 'section id'),
        };
        if (sections.isEmpty) throw const _Usage('An option needs at least one value.');
      case 'asof':
        asOf = DateTime.tryParse(raw) ?? (throw _Usage('asof is YYYY-MM-DD'));
      default:
        throw _Usage('Unknown option "$key". $_options');
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

// ---- classes (part 2) ----

String _classesText(List<SrpClassView> classes, String header) {
  final out = StringBuffer(header);
  if (classes.isEmpty) out.write('\n(no SRP classes)');
  for (final c in classes) {
    final k = c.srpClass;
    out.write('\n${k.className} (#${k.id}) · ${k.assessedLabel} · ${c.learners.length} learner(s)'
        ' · room ${k.room ?? '-'} · ${k.schedule ?? 'no schedule'} · tutor ${c.tutor?.fullName ?? (k.tutorId == null ? '-' : k.tutorId!)}');
    for (final (i, l) in c.learners.indexed) {
      out.write('\n  ${i + 1}. ${l.name} (#${l.member.studentId}${l.student == null ? '' : ', ${l.student!.lrn}'})'
          '${l.section == null ? '' : ' · G${l.section!.gradeLevel} ${l.section!.sectionName}'}');
    }
  }
  return out.toString();
}

String _withWarning(SrpViewModel vm, String text) =>
    vm.lastMirrorWarning == null ? text : '$text\nWARNING: ${vm.lastMirrorWarning}';

void registerSrpCommands(ConsoleRegistry registry, SrpViewModel vm) {
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

  add('srp-list', 'srp-list <schoolId> <schoolYear> $_options — Summer Remediation Program candidates, '
      'weakest first', (args) async {
    if (args.length < 2) throw const _Usage('Usage: srp-list <schoolId> <schoolYear> $_options');
    final o = _filter(args.sublist(2));
    final list = await vm.candidates(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    if (list.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _text(list, o.recommendedOnly);
  });

  add('srp-build', 'srp-build <schoolId> <schoolYear> [per=<n, default 15>] [size=<n, default 15>] '
      '[asof=YYYY-MM-DD] — build the SRP classes from the recommended learners (online)', (args) async {
    if (args.length < 2) throw const _Usage('Usage: srp-build <schoolId> <schoolYear> [per=n] [size=n] [asof=YYYY-MM-DD]');
    var per = srpDefaultPerSection, size = srpDefaultClassSize;
    DateTime? asOf;
    for (final o in args.sublist(2)) {
      final eq = o.indexOf('=');
      final raw = eq < 0 ? '' : o.substring(eq + 1).trim();
      switch (eq < 0 ? o : o.substring(0, eq)) {
        case 'per':
          per = _int(raw, 'per');
        case 'size':
          size = _int(raw, 'size');
        case 'asof':
          asOf = DateTime.tryParse(raw) ?? (throw const _Usage('asof is YYYY-MM-DD'));
        default:
          throw _Usage('Unknown option "$o". Options: per=n size=n asof=YYYY-MM-DD');
      }
    }
    final classes = await vm.buildClasses(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], perSection: per, classSize: size, asOf: asOf);
    return _withWarning(vm, _classesText(classes, 'Built ${classes.length} SRP class(es):'));
  });

  add('srp-classes', 'srp-classes <schoolId> <schoolYear> — the SRP classes on this device (a tutor: their own)',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: srp-classes <schoolId> <schoolYear>');
    final classes = await vm.classes(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1]);
    return _classesText(classes, 'SRP classes | school ${args[0]} | ${args[1]}');
  });

  add('srp-classes-csv', 'srp-classes-csv <schoolId> <schoolYear> <out.csv> — the SRP masterlist as CSV', (args) async {
    if (args.length != 3) throw const _Usage('Usage: srp-classes-csv <schoolId> <schoolYear> <out.csv>');
    final classes = await vm.classes(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1]);
    await File(args[2]).writeAsString(srpClassesCsv(classes));
    return 'Wrote ${args[2]} (${classes.length} class(es), '
        '${classes.fold<int>(0, (n, c) => n + c.learners.length)} learner(s)).';
  });

  add('srp-class-set', 'srp-class-set <classId|name> [name=..] [room=..|-] [schedule=..|-] [tutor=<email>|-] — change a '
      'class (online; quote values with spaces: "schedule=MWF 8-10")', (args) async {
    if (args.length < 2) {
      throw const _Usage('Usage: srp-class-set <classId|name> [name=..] [room=..|-] [schedule=..|-] [tutor=<email>|-]');
    }
    String? name, room, schedule, tutor;
    var clearRoom = false, clearSchedule = false, clearTutor = false;
    for (final o in args.sublist(1)) {
      final eq = o.indexOf('=');
      if (eq < 0) throw _Usage('Options look like key=value (got "$o").');
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
          throw _Usage('Unknown option "${o.substring(0, eq)}". Options: name= room= schedule= tutor=');
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
    return _withWarning(vm, _classesText([c], 'Saved:'));
  });

  add('srp-add', 'srp-add <classId|name> <studentId> — put a learner in an SRP class (online)', (args) async {
    if (args.length != 2) throw const _Usage('Usage: srp-add <classId|name> <studentId>');
    final c = await vm.addLearner(await vm.classIdFor(args[0]), _int(args[1], 'studentId'));
    return _withWarning(vm, _classesText([c], 'Added:'));
  });

  add('srp-move', 'srp-move <studentId> <toClassId|name> — move a learner to another SRP class (online)', (args) async {
    if (args.length != 2) throw const _Usage('Usage: srp-move <studentId> <toClassId|name>');
    final c = await vm.moveLearner(_int(args[0], 'studentId'), await vm.classIdFor(args[1]));
    return _withWarning(vm, _classesText([c], 'Moved:'));
  });

  add('srp-remove', 'srp-remove <classId|name> <studentId> — take a learner out of an SRP class (online)', (args) async {
    if (args.length != 2) throw const _Usage('Usage: srp-remove <classId|name> <studentId>');
    final c = await vm.removeLearner(await vm.classIdFor(args[0]), _int(args[1], 'studentId'));
    return _withWarning(vm, _classesText([c], 'Removed:'));
  });

  add('srp-class-delete', 'srp-class-delete <classId|name> — delete an SRP class and take its learners out (online)',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: srp-class-delete <classId|name>');
    await vm.deleteClass(await vm.classIdFor(args[0]));
    return _withWarning(vm, 'Deleted SRP class ${args[0]}.');
  });

  add('srp-classes-clear', 'srp-classes-clear <schoolId> <schoolYear> yes — delete ALL the school\'s SRP classes '
      'for the year (online)', (args) async {
    if (args.length != 3 || args[2] != 'yes') {
      throw const _Usage('This deletes every SRP class of the school for that year. '
          'Usage: srp-classes-clear <schoolId> <schoolYear> yes');
    }
    final n = await vm.clearClasses(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1]);
    return _withWarning(vm, 'Deleted $n SRP class(es).');
  });

  add('srp-list-csv','srp-list-csv <schoolId> <schoolYear> <out.csv> $_options — the same as CSV', (args) async {
    if (args.length < 3) throw const _Usage('Usage: srp-list-csv <schoolId> <schoolYear> <out.csv> $_options');
    final o = _filter(args.sublist(3));
    final list = await vm.candidates(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    await File(args[2]).writeAsString(srpListCsv(list, recommendedOnly: o.recommendedOnly));
    final n = list.sections.fold<int>(
        0, (n, s) => n + (o.recommendedOnly ? s.recommendedCount : s.candidates.length));
    return 'Wrote ${args[2]} ($n learner(s)).';
  });
}
