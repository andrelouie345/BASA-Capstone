// lib/core/console/commands/aral_material_admin_commands.dart
// Admin build only: the admin half of aral_material_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_material_viewmodel.dart';
import '../../models/aral_enrollment.dart';
import '../../models/aral_material.dart';
import 'aral_material_command_helpers.dart';

void registerAralMaterialAdminCommands(ConsoleRegistry registry, AralMaterialViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralMaterialUsage catch (e) {
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
    throw AralMaterialUsage(hits.isEmpty
        ? 'No material titled "$raw" on this device (aral-materials lists them).'
        : '${hits.length} materials are titled "$raw" (one per owner); use the #id.');
  }

  String withWarning(String text) {
    final warn = vm.lastMirrorWarning;
    return warn == null ? text : '$text\n$warn';
  }

  add(
      'aral-material-add',
      'aral-material-add <region|schoolId> <foundational|ks1|ks2|ks3> <basic|plus|any> <learner|tutor|supplementary> '
          '<English|Filipino> "<title>" [grades=7-10] ["file=<file name>"] [link=<url>] — add a material to the '
          'catalog (online)', (args) async {
    const usage = 'Usage: aral-material-add <region|schoolId> <foundational|ks1|ks2|ks3> <basic|plus|any> '
        '<learner|tutor|supplementary> <English|Filipino> "<title>" [grades=7-10] ["file=<file name>"] [link=<url>]';
    if (args.length < 6 || args.length > 9) throw const AralMaterialUsage(usage);
    var grades = (aralMaterialDefaultMinGrade, aralMaterialDefaultMaxGrade);
    String? file, link;
    for (final opt in args.sublist(6)) {
      if (opt.startsWith('grades=')) {
        grades = _grades(opt.substring(7));
      } else if (opt.startsWith('file=')) {
        file = opt.substring(5);
      } else if (opt.startsWith('link=')) {
        link = opt.substring(5);
      } else {
        throw const AralMaterialUsage(usage);
      }
    }
    final m = await vm.addMaterial(
      schoolId: args[0] == 'region' ? null : aralMaterialInt(args[0], 'schoolId'),
      keyStage: _keyStage(args[1]),
      track: _track(args[2]),
      kind: _kind(args[3]),
      language: _language(args[4]),
      title: args[5],
      minGrade: grades.$1,
      maxGrade: grades.$2,
      fileName: file,
      link: link,
    );
    return withWarning('Added ${aralMaterialLine(m)}');
  });

  add(
      'aral-material-set',
      'aral-material-set <id|"title"> <title|program|kind|language|grades|description|file|link> <value...> — change '
          'a material (online; program = <ks> <basic|plus|any>, grades = 7-10; "-" clears description, file, link)',
      (args) async {
    const usage =
        'Usage: aral-material-set <id|"title"> <title|program|kind|language|grades|description|file|link> <value...>';
    if (args.length < 3) throw const AralMaterialUsage(usage);
    final id = await ref(args[0]);
    final value = args.sublist(2).join(' ');
    final m = switch (args[1]) {
      'title' => await vm.updateMaterial(id, title: value),
      'program' => args.length == 4
          ? await vm.updateMaterial(id, keyStage: _keyStage(args[2]), track: () => _track(args[3]))
          : throw const AralMaterialUsage('Usage: aral-material-set <id> program <ks> <basic|plus|any>'),
      'kind' => await vm.updateMaterial(id, kind: _kind(value)),
      'language' => await vm.updateMaterial(id, language: _language(value)),
      'grades' => await () {
          final g = _grades(value);
          return vm.updateMaterial(id, minGrade: g.$1, maxGrade: g.$2);
        }(),
      'description' => await vm.updateMaterial(id, description: () => value == '-' ? null : value),
      'file' => await vm.updateMaterial(id, fileName: () => value == '-' ? null : value),
      'link' => await vm.updateMaterial(id, link: () => value == '-' ? null : value),
      _ => throw const AralMaterialUsage(usage),
    };
    return withWarning('Saved ${aralMaterialLine(m)}');
  });

  add('aral-material-active', 'aral-material-active <id|"title"> <on|off> — retire a material or bring it back (online)',
      (args) async {
    if (args.length != 2 || (args[1] != 'on' && args[1] != 'off')) {
      throw const AralMaterialUsage('Usage: aral-material-active <id> <on|off>');
    }
    final m = await vm.setActive(await ref(args[0]), args[1] == 'on');
    return withWarning('Saved ${aralMaterialLine(m)}');
  });

  add('aral-material-delete', 'aral-material-delete <id|"title"> — remove a material from the catalog (online)',
      (args) async {
    if (args.length != 1) throw const AralMaterialUsage('Usage: aral-material-delete <id|"title">');
    final id = await ref(args[0]);
    await vm.deleteMaterial(id);
    return withWarning('Deleted material #$id.');
  });

  add(
      'aral-material-school-link',
      "aral-material-school-link <id|\"title\"> <schoolId> <url|-> — a school's own link for a material it can see "
          "(online; '-' removes it; the school's learners get this link instead of the material's)", (args) async {
    if (args.length != 3) throw const AralMaterialUsage('Usage: aral-material-school-link <id|"title"> <schoolId> <url|->');
    final id = await ref(args[0]);
    final schoolId = aralMaterialInt(args[1], 'schoolId');
    final saved = await vm.setSchoolLink(id, schoolId, args[2] == '-' ? null : args[2]);
    return withWarning(saved == null
        ? 'School $schoolId has no own link for material #$id any more.'
        : 'School $schoolId link for material #$id: ${saved.link}');
  });

  add('aral-recommend-section',
      'aral-recommend-section <sectionId> <schoolYear> — the materials for every active ARAL learner of a section',
      (args) async {
    if (args.length != 2) throw const AralMaterialUsage('Usage: aral-recommend-section <sectionId> <schoolYear>');
    final list = await vm.sectionRecommendations(sectionId: aralMaterialInt(args[0], 'sectionId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No active ARAL learners in section ${args[0]} for ${args[1]}.';
    return list.map(aralMaterialRecommendation).join('\n');
  });
}

AralKeyStage _keyStage(String raw) {
  try {
    return AralKeyStage.fromString(raw.toLowerCase());
  } on ArgumentError {
    throw AralMaterialUsage('Program is foundational, ks1, ks2 or ks3 (got "$raw")');
  }
}

/// basic / plus, or "any"/"-" for none (Foundational, KS1, or either KS2/KS3 track).
AralTrack? _track(String raw) => switch (raw.toLowerCase()) {
      'basic' => AralTrack.basic,
      'plus' => AralTrack.plus,
      'any' || '-' => null,
      _ => throw AralMaterialUsage('Track is basic, plus or any (got "$raw")'),
    };

AralMaterialKind _kind(String raw) {
  try {
    return AralMaterialKind.fromString(raw.toLowerCase());
  } on ArgumentError {
    throw AralMaterialUsage('Kind is learner, tutor or supplementary (got "$raw")');
  }
}

String _language(String raw) => aralMaterialLanguages.firstWhere((l) => l.toLowerCase() == raw.toLowerCase(),
    orElse: () => throw AralMaterialUsage('Language is ${aralMaterialLanguages.join(' or ')} (got "$raw")'));

(int, int) _grades(String raw) {
  final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(raw);
  if (m == null) throw AralMaterialUsage('Grades are written like 7-10 (got "$raw")');
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}
