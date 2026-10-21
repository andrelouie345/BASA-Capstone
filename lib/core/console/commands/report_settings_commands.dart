// lib/core/console/commands/report_settings_commands.dart

/// Report settings (dashboard D2): the progress "done" threshold per region
/// (superadmin) and school (its admin/coordinator). report-settings-show reads
/// this device's copy; set/reset are online. `region` = the region-wide row.
/// Sync S6 adds sync-auto-approve and offline-days[-set] (same rows).
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
      "report-settings-reset <schoolId> — drop the school's done threshold, auto-approve and offline window so the "
          "region's apply (online)",
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: report-settings-reset <schoolId>');
    final schoolId = _school(args[0]);
    if (schoolId == null) throw const _Usage('Only a school override can be reset, not the region row.');
    await vm.resetSchool(schoolId);
    return 'School $schoolId now uses the region report settings.${warn()}';
  });

  String onOff(bool? v) => v == null ? 'not set' : (v ? 'on' : 'off');
  String days(int? v) => v == null ? 'not set' : '$v days';

  add('sync-auto-approve',
      "sync-auto-approve <region|schoolId> [on|off] — show (this device's copy) or set whether tutors' uploads "
          'apply without an approver (online)', (args) async {
    const usage = 'Usage: sync-auto-approve <region|schoolId> [on|off]';
    if (args.isEmpty || args.length > 2) throw const _Usage(usage);
    final schoolId = _school(args[0]);
    if (args.length == 1) {
      final l = await vm.autoApproveLayers(schoolId);
      return 'Auto-approve: region ${onOff(l.region)}'
          '${schoolId == null ? '' : ' · school ${onOff(l.school)}'} · applies ${onOff(l.effective)}';
    }
    if (!const ['on', 'off'].contains(args[1])) throw const _Usage(usage);
    final on = args[1] == 'on';
    await vm.setAutoApprove(schoolId, on);
    return 'Auto-approve for ${_who(schoolId)} is now ${onOff(on)}.'
        '${on ? '\nUploads already waiting still need sync-approve.' : ''}${warn()}';
  });

  add('offline-days',
      'offline-days <region|schoolId> — the offline sign-in window: region, school, the one that applies',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: offline-days <region|schoolId>');
    final schoolId = _school(args[0]);
    final l = await vm.offlineDaysLayers(schoolId);
    return 'Offline sign-in window: region ${days(l.region)}'
        '${schoolId == null ? '' : ' · school ${days(l.school)}'} · applies ${l.effective} days';
  });

  add('offline-days-set',
      'offline-days-set <region|schoolId> <1-60> — set the offline sign-in window in days (online)', (args) async {
    const usage = 'Usage: offline-days-set <region|schoolId> <1-60>';
    if (args.length != 2) throw const _Usage(usage);
    final schoolId = _school(args[0]);
    final n = int.tryParse(args[1]);
    if (n == null) throw _Usage('The window is a whole number of days (got "${args[1]}"). $usage');
    await vm.setOfflineDays(schoolId, n);
    return 'Offline sign-in window for ${_who(schoolId)}: $n days. Tablets get it after their next pull-cloud.'
        '${warn()}';
  });
}
