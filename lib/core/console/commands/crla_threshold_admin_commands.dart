// lib/core/console/commands/crla_threshold_admin_commands.dart
// Admin build only: the admin half of crla_threshold_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/crla_threshold_viewmodel.dart';
import 'crla_threshold_command_helpers.dart';

void registerCrlaThresholdAdminCommands(ConsoleRegistry registry, CrlaThresholdViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on CrlaThresholdUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  String done(String message) =>
      vm.lastMirrorWarning == null ? message : '$message\nWARNING: ${vm.lastMirrorWarning}';

  add(
      'crla-threshold-set',
      'crla-threshold-set <schoolId|region> <key> <value|clear> — set one CRLA threshold '
          '(whole numbers or true/false; clear = use the layer below). Only new assessments use it.', (args) async {
    if (args.length != 3) throw const CrlaThresholdUsage('Usage: crla-threshold-set <schoolId|region> <key> <value|clear>');
    final schoolId = args[0] == 'region' ? null : crlaThresholdInt(args[0], 'schoolId');
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
    if (args.length != 1) throw const CrlaThresholdUsage('Usage: crla-threshold-reset <schoolId>');
    final schoolId = crlaThresholdInt(args[0], 'schoolId');
    await vm.resetSchoolThresholds(schoolId);
    return done('School $schoolId now uses the region CRLA thresholds.');
  });

  add(
      'crla-regenerate',
      'crla-regenerate <assessmentId> [assessmentId...] — admin/coordinator: re-score cloud CRLA assessments '
          'with today\'s thresholds (all or nothing)', (args) async {
    if (args.isEmpty) throw const CrlaThresholdUsage('Usage: crla-regenerate <assessmentId> [assessmentId...]');
    final ids = [for (final a in args) crlaThresholdInt(a, 'assessmentId')];
    final n = await vm.regenerate(ids);
    return done('Re-scored $n CRLA assessment(s) with today\'s thresholds.');
  });
}
