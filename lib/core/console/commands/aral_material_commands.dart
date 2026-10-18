// lib/core/console/commands/aral_material_commands.dart

/// Commands for the ARAL material catalog (online: add/change/delete) and the
/// recommendations (offline, from this device's copy). One action per
/// command; the ViewModel does the checks. Materials are named by the #id
/// aral-materials shows; learners by their ARAL enrollment id (aral-roster).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_material_viewmodel.dart';
import '../../models/aral_enrollment.dart';
import '../../models/aral_material.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

AralKeyStage _keyStage(String raw) {
  try {
    return AralKeyStage.fromString(raw.toLowerCase());
  } on ArgumentError {
    throw _Usage('Program is foundational, ks1, ks2 or ks3 (got "$raw")');
  }
}

/// basic / plus, or "any"/"-" for none (Foundational, KS1, or either KS2/KS3 track).
AralTrack? _track(String raw) => switch (raw.toLowerCase()) {
      'basic' => AralTrack.basic,
      'plus' => AralTrack.plus,
      'any' || '-' => null,
      _ => throw _Usage('Track is basic, plus or any (got "$raw")'),
    };

AralMaterialKind _kind(String raw) {
  try {
    return AralMaterialKind.fromString(raw.toLowerCase());
  } on ArgumentError {
    throw _Usage('Kind is learner, tutor or supplementary (got "$raw")');
  }
}

String _language(String raw) => aralMaterialLanguages.firstWhere((l) => l.toLowerCase() == raw.toLowerCase(),
    orElse: () => throw _Usage('Language is ${aralMaterialLanguages.join(' or ')} (got "$raw")'));

(int, int) _grades(String raw) {
  final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(raw);
  if (m == null) throw _Usage('Grades are written like 7-10 (got "$raw")');
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

String _line(AralMaterial m) => '#${m.id} | ${m.title} | ${m.programLabel} | ${m.kind.label} | ${m.language} | '
    'Grades ${m.minGrade}-${m.maxGrade} | ${m.schoolId == null ? 'region-wide' : 'school ${m.schoolId}'}'
    '${m.isActive ? '' : ' | RETIRED'} | ${m.hasFile ? 'file ${m.fileName}' : 'no file yet'}';

String _recommendation(AralRecommendation r) {
  final e = r.enrollment;
  final head = '#${e.id} | student ${e.studentId} | Grade ${r.grade} | ${e.programLabel}';
  if (r.materials.isEmpty) return '$head\n  ${r.note ?? 'nothing'}';
  return [head, for (final m in r.materials) '  - ${m.title} (${m.kind.label}, ${m.language})'].join('\n');
}

void registerAralMaterialCommands(ConsoleRegistry registry, AralMaterialViewModel vm) {
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

  /// A material by #id, or by its exact title (case-insensitive) on this device.
  Future<int> ref(String raw) async {
    final id = int.tryParse(raw.startsWith('#') ? raw.substring(1) : raw);
    if (id != null) return id;
    final hits = (await vm.catalog()).where((m) => m.title.toLowerCase() == raw.toLowerCase()).toList();
    if (hits.length == 1) return hits.single.id!;
    throw _Usage(hits.isEmpty
        ? 'No material titled "$raw" on this device (aral-materials lists them).'
        : '${hits.length} materials are titled "$raw" (one per owner); use the #id.');
  }

  String withWarning(String text) {
    final warn = vm.lastMirrorWarning;
    return warn == null ? text : '$text\n$warn';
  }

  add('aral-materials', 'aral-materials [active] — the ARAL material catalog on this device', (args) async {
    final list = await vm.catalog(activeOnly: args.isNotEmpty && args.first == 'active');
    if (list.isEmpty) return 'No ARAL materials on this device (add some, or pull-cloud).';
    return list.map(_line).join('\n');
  });

  add(
      'aral-material-add',
      'aral-material-add <region|schoolId> <foundational|ks1|ks2|ks3> <basic|plus|any> <learner|tutor|supplementary> '
          '<English|Filipino> "<title>" [grades=7-10] — add a material to the catalog (online)', (args) async {
    const usage = 'Usage: aral-material-add <region|schoolId> <foundational|ks1|ks2|ks3> <basic|plus|any> '
        '<learner|tutor|supplementary> <English|Filipino> "<title>" [grades=7-10]';
    if (args.length < 6 || args.length > 7) throw const _Usage(usage);
    var grades = (aralMaterialDefaultMinGrade, aralMaterialDefaultMaxGrade);
    if (args.length == 7) {
      if (!args[6].startsWith('grades=')) throw const _Usage(usage);
      grades = _grades(args[6].substring(7));
    }
    final m = await vm.addMaterial(
      schoolId: args[0] == 'region' ? null : _int(args[0], 'schoolId'),
      keyStage: _keyStage(args[1]),
      track: _track(args[2]),
      kind: _kind(args[3]),
      language: _language(args[4]),
      title: args[5],
      minGrade: grades.$1,
      maxGrade: grades.$2,
    );
    return withWarning('Added ${_line(m)}');
  });

  add(
      'aral-material-set',
      'aral-material-set <id|"title"> <title|program|kind|language|grades|description> <value...> — change a material '
          '(online; program = <ks> <basic|plus|any>, grades = 7-10, description "-" clears)', (args) async {
    const usage = 'Usage: aral-material-set <id> <title|program|kind|language|grades|description> <value...>';
    if (args.length < 3) throw const _Usage(usage);
    final id = await ref(args[0]);
    final value = args.sublist(2).join(' ');
    final m = switch (args[1]) {
      'title' => await vm.updateMaterial(id, title: value),
      'program' => args.length == 4
          ? await vm.updateMaterial(id, keyStage: _keyStage(args[2]), track: () => _track(args[3]))
          : throw const _Usage('Usage: aral-material-set <id> program <ks> <basic|plus|any>'),
      'kind' => await vm.updateMaterial(id, kind: _kind(value)),
      'language' => await vm.updateMaterial(id, language: _language(value)),
      'grades' => await () {
          final g = _grades(value);
          return vm.updateMaterial(id, minGrade: g.$1, maxGrade: g.$2);
        }(),
      'description' => await vm.updateMaterial(id, description: () => value == '-' ? null : value),
      _ => throw const _Usage(usage),
    };
    return withWarning('Saved ${_line(m)}');
  });

  add('aral-material-active', 'aral-material-active <id|"title"> <on|off> — retire a material or bring it back (online)',
      (args) async {
    if (args.length != 2 || (args[1] != 'on' && args[1] != 'off')) {
      throw const _Usage('Usage: aral-material-active <id> <on|off>');
    }
    final m = await vm.setActive(await ref(args[0]), args[1] == 'on');
    return withWarning('Saved ${_line(m)}');
  });

  add('aral-material-delete', 'aral-material-delete <id|"title"> — remove a material from the catalog (online)',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: aral-material-delete <id|"title">');
    final id = await ref(args[0]);
    await vm.deleteMaterial(id);
    return withWarning('Deleted material #$id.');
  });

  add('aral-recommend', 'aral-recommend <enrollmentId> — the materials for one ARAL learner (offline)', (args) async {
    if (args.length != 1) throw const _Usage('Usage: aral-recommend <enrollmentId>');
    return _recommendation(await vm.recommendations(_int(args[0], 'enrollmentId')));
  });

  add('aral-recommend-section',
      'aral-recommend-section <sectionId> <schoolYear> — the materials for every active ARAL learner of a section',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: aral-recommend-section <sectionId> <schoolYear>');
    final list = await vm.sectionRecommendations(sectionId: _int(args[0], 'sectionId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No active ARAL learners in section ${args[0]} for ${args[1]}.';
    return list.map(_recommendation).join('\n');
  });
}
