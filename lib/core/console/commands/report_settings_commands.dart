// lib/core/console/commands/report_settings_commands.dart

/// Report settings (dashboard D2): the progress "done" threshold per region
/// (superadmin) and school (its admin/coordinator). report-settings-show reads
/// this device's copy; set/reset are online. `region` = the region-wide row.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/report_settings_viewmodel.dart';
import '../../models/report_setting.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int? _school(String raw) =>
    raw.toLowerCase() == 'region' ? null : int.tryParse(raw) ?? (throw _Usage('Invalid school: "$raw" (a school id or region)'));

String _who(int? schoolId) => schoolId == null ? 'the region' : 'school $schoolId';

void registerReportSettingsCommands(ConsoleRegistry registry, ReportSettingsViewModel vm) {
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

  String warn() => vm.lastMirrorWarning == null ? '' : '\n${vm.lastMirrorWarning}';
  String show(double? share) => share == null ? 'not set' : thresholdPercent(share);

  add('report-settings-show',
      'report-settings-show <region|schoolId> — the progress done threshold: region, school, the one that applies',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: report-settings-show <region|schoolId>');
    final schoolId = _school(args[0]);
    final l = await vm.doneThresholdLayers(schoolId);
    return 'Done threshold: region ${show(l.region)}'
        '${schoolId == null ? '' : ' · school ${show(l.school)}'} · applies ${thresholdPercent(l.effective)}';
  });

  add('report-settings-set',
      'report-settings-set <region|schoolId> <percent 1-100> — set the progress done threshold (online)', (args) async {
    const usage = 'Usage: report-settings-set <region|schoolId> <percent 1-100>';
    if (args.length != 2) throw const _Usage(usage);
    final schoolId = _school(args[0]);
    final pct = double.tryParse(args[1].replaceAll('%', ''));
    if (pct == null || pct < 1 || pct > 100) throw _Usage('The percent must be 1-100 (got "${args[1]}"). $usage');
    final saved = await vm.setDoneThreshold(schoolId, pct / 100);
    final share = (saved.settings[ReportSettings.doneThresholdKey] as num).toDouble();
    return 'Done threshold for ${_who(schoolId)}: ${thresholdPercent(share)}.${warn()}';
  });

  add('report-settings-reset',
      "report-settings-reset <schoolId> — drop a school's report settings so the region's apply (online)",
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: report-settings-reset <schoolId>');
    final schoolId = _school(args[0]);
    if (schoolId == null) throw const _Usage('Only a school override can be reset, not the region row.');
    await vm.resetSchool(schoolId);
    return 'School $schoolId now uses the region report settings.${warn()}';
  });
}
