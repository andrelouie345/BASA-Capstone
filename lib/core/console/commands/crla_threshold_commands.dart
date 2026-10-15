// lib/core/console/commands/crla_threshold_commands.dart

/// Commands for the adjustable CRLA thresholds (online) and re-scoring.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/crla_threshold_viewmodel.dart';
import '../../services/crla_rules.dart';

void registerCrlaThresholdCommands(ConsoleRegistry registry, CrlaThresholdViewModel vm) {
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

  String done(String message) =>
      vm.lastMirrorWarning == null ? message : '$message\nWARNING: ${vm.lastMirrorWarning}';

  add('crla-thresholds', 'crla-thresholds [schoolId] — region and school CRLA threshold rows and the values that apply',
      (args) async {
    final schoolId = args.isEmpty ? null : _int(args[0], 'schoolId');
    final layers = await vm.thresholdLayers(schoolId);
    final region = layers.region?.settings ?? const {};
    final school = layers.school?.settings ?? const {};
    final out = StringBuffer('Region row: ${layers.region == null ? 'none (defaults)' : '${region.length} key(s)'}');
    if (schoolId != null) {
      out.write('; school $schoolId override: ${layers.school == null ? 'none' : '${school.length} key(s)'}');
    }
    final defaults = CrlaThresholds.defaults.toMap();
    layers.effective.toMap().forEach((key, value) {
      final from = school.containsKey(key) ? 'school' : (region.containsKey(key) ? 'region' : 'default');
      final note = from == 'default' ? '' : '   ($from; default ${defaults[key]})';
      out.write('\n  ${key.padRight(36)} $value$note');
    });
    return out.toString();
  });

  add(
      'crla-threshold-set',
      'crla-threshold-set <schoolId|region> <key> <value|clear> — set one CRLA threshold '
          '(whole numbers or true/false; clear = use the layer below). Only new assessments use it.', (args) async {
    if (args.length != 3) throw const _Usage('Usage: crla-threshold-set <schoolId|region> <key> <value|clear>');
    final schoolId = args[0] == 'region' ? null : _int(args[0], 'schoolId');
    final value = switch (args[2]) {
      'clear' => null,
      'true' => true,
      'false' => false,
      final raw => int.tryParse(raw) ?? raw, // the ViewModel names the expected type
    };
    final saved = await vm.saveThresholds(schoolId: schoolId, changes: {args[1]: value});
    return done('Saved ${schoolId == null ? 'region' : 'school $schoolId'} CRLA thresholds: ${saved.settings}');
  });

  add('crla-threshold-reset', 'crla-threshold-reset <schoolId> — remove a school\'s CRLA override (region values apply)',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: crla-threshold-reset <schoolId>');
    final schoolId = _int(args[0], 'schoolId');
    await vm.resetSchoolThresholds(schoolId);
    return done('School $schoolId now uses the region CRLA thresholds.');
  });

  add(
      'crla-regenerate',
      'crla-regenerate <assessmentId> [assessmentId...] — admin/coordinator: re-score cloud CRLA assessments '
          'with today\'s thresholds (all or nothing)', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: crla-regenerate <assessmentId> [assessmentId...]');
    final ids = [for (final a in args) _int(a, 'assessmentId')];
    final n = await vm.regenerate(ids);
    return done('Re-scored $n CRLA assessment(s) with today\'s thresholds.');
  });
}

/// A bad argument: the handler returns the message as-is.
class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String name) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $name: "$raw" (expected a number)'));
