// lib/ui/admin/report_screens.dart
// Reports (docs/handoff/screens/reports.md): the NLA portal report with its
// filters, progress monitoring, the BOSY masterlist, and the report
// settings (done threshold, auto-approve, offline sign-in days). Each
// report shows the ViewModel's CSV as a table and saves it. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/report_setting.dart';
import '../../viewmodels/nla_report_viewmodel.dart';
import '../common/csv_table.dart';
import '../common/screen_kit.dart';
import '../common/school_year_scope.dart';

String _sexLabel(NlaSex s) => switch (s) {
  NlaSex.male => 'Male',
  NlaSex.female => 'Female',
  NlaSex.total => 'Total',
};

String _blockLabel(NlaBlock b) => switch (b) {
  NlaBlock.enrolment => 'Enrolment',
  NlaBlock.gst => 'GST',
  NlaBlock.profile => 'Profile',
  NlaBlock.form2b => 'Form 2b',
  NlaBlock.aral => 'ARAL',
};

class NlaReportScreen extends StatefulWidget {
  const NlaReportScreen({super.key});

  @override
  State<NlaReportScreen> createState() => _NlaReportScreenState();
}

class _NlaReportScreenState extends State<NlaReportScreen> {
  Set<NlaSex> _sexes = {...NlaSex.values};
  Set<PhilIriRound> _rounds = {...PhilIriRound.values};
  Set<NlaBlock> _blocks = {...NlaBlock.values};

  Widget _chips<T>(String label, List<T> all, Set<T> on, String Function(T) name, ValueChanged<Set<T>> set) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(width: 70, child: Text(label)),
      for (final x in all)
        FilterChip(
          label: Text(name(x)),
          selected: on.contains(x),
          onSelected: (v) => set(v ? {...on, x} : ({...on}..remove(x))),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final filter = NlaReportFilter(sexes: _sexes, rounds: _rounds, blocks: _blocks);
    return Scaffold(
      appBar: AppBar(title: const Text('NLA portal report')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          _chips('Sex', NlaSex.values, _sexes, _sexLabel, (s) => setState(() => _sexes = s)),
          _chips('Round', PhilIriRound.values, _rounds, (r) => r.label, (s) => setState(() => _rounds = s)),
          _chips('Block', NlaBlock.values, _blocks, _blockLabel, (s) => setState(() => _blocks = s)),
          SchoolYearScope(
            builder: (context, schoolId, year) => LoadView<NlaReport>(
              where: 'NlaReport',
              reloadKey: '$schoolId-$year',
              load: (vms) => vms.nlaReport.report(schoolId: schoolId, schoolYear: year),
              builder: (context, r, _) => CsvTableView(csv: nlaReportCsv(r, filter), fileName: 'NLA_report_$year.csv'),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress monitoring')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          SchoolYearScope(
            builder: (context, schoolId, year) => LoadView<ProgressReport>(
              where: 'Progress',
              reloadKey: '$schoolId-$year',
              load: (vms) => vms.nlaReport.progress(schoolId: schoolId, schoolYear: year),
              builder: (context, r, _) => CsvTableView(csv: progressReportCsv(r), fileName: 'progress_$year.csv'),
            ),
          ),
        ],
      ),
    );
  }
}

class BosyMasterlistScreen extends StatelessWidget {
  const BosyMasterlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BOSY masterlist')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          const Text('Learners not grade-level ready at the beginning of the school year.'),
          SchoolYearScope(
            builder: (context, schoolId, year) => LoadView<BosyMasterlist>(
              where: 'BosyMasterlist',
              reloadKey: '$schoolId-$year',
              load: (vms) => vms.nlaReport.bosyMasterlist(schoolId: schoolId, schoolYear: year),
              builder: (context, l, _) => CsvTableView(csv: bosyMasterlistCsv(l), fileName: 'BOSY_masterlist_$year.csv'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Settings {
  final ({double? region, double? school, double effective}) done;
  final ({bool? region, bool? school, bool effective}) auto;
  final ({int? region, int? school, int effective}) offline;
  const _Settings(this.done, this.auto, this.offline);
}

class ReportSettingsScreen extends StatefulWidget {
  const ReportSettingsScreen({super.key});

  @override
  State<ReportSettingsScreen> createState() => _ReportSettingsScreenState();
}

class _ReportSettingsScreenState extends State<ReportSettingsScreen> {
  int _reload = 0;

  Future<void> _set(int? schoolId, String what, Object current) async {
    final vm = vmsOf(context).reportSettings;
    Object? r;
    if (current is bool) {
      final on = await pickOne<bool>(context, title: 'Approve uploads automatically', options: const [true, false], label: (b) => b ? 'On' : 'Off');
      if (on == null || !mounted) return;
      r = await runAction(context, () => vm.setAutoApprove(schoolId, on), done: 'Saved.', where: 'ReportSettings');
    } else {
      final f = await askFields(context,
          title: what == 'done' ? 'Done threshold (%)' : 'Offline sign-in days',
          fields: [FieldSpec('v', 'Value', initial: what == 'done' ? ((current as double) * 100).toStringAsFixed(1) : '$current', number: true)]);
      if (f == null || !mounted) return;
      if (what == 'done') {
        final pct = double.tryParse(f['v']!);
        if (pct == null) return;
        r = await runAction(context, () => vm.setDoneThreshold(schoolId, pct / 100), done: 'Saved.', where: 'ReportSettings');
      } else {
        final days = int.tryParse(f['v']!);
        if (days == null) return;
        r = await runAction(context, () => vm.setOfflineDays(schoolId, days), done: 'Saved.', where: 'ReportSettings');
      }
    }
    if (r != null && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    return Scaffold(
      appBar: AppBar(title: const Text('Report settings')),
      body: LoadView<_Settings>(
        where: 'ReportSettings',
        reloadKey: _reload,
        load: (vms) async {
          final s = vms.reportSettings;
          return _Settings(await s.doneThresholdLayers(schoolId), await s.autoApproveLayers(schoolId), await s.offlineDaysLayers(schoolId));
        },
        builder: (context, l, _) {
          String pct(double? v) => v == null ? '—' : thresholdPercent(v);
          String yn(bool? v) => v == null ? '—' : (v ? 'on' : 'off');
          Widget row(String title, String effective, String region, String school, VoidCallback onEdit) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: Text('Region: $region · School: $school'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(effective, style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            ]),
          );
          return PageBody(children: [
            Text(schoolId == null ? 'Region defaults.' : 'In force at your school.'),
            SectionCard(title: 'Settings', children: [
              row('Done threshold', pct(l.done.effective), pct(l.done.region), pct(l.done.school), () => _set(schoolId, 'done', l.done.effective)),
              row('Approve uploads automatically', yn(l.auto.effective), yn(l.auto.region), yn(l.auto.school),
                  () => _set(schoolId, 'auto', l.auto.effective)),
              row('Offline sign-in days', '${l.offline.effective}', '${l.offline.region ?? '—'}', '${l.offline.school ?? '—'}',
                  () => _set(schoolId, 'offline', l.offline.effective)),
            ]),
            if (schoolId != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text("Use the region's settings"),
                onPressed: () async {
                  if (!await confirm(context, title: "Use the region's settings?", action: 'Reset') || !context.mounted) return;
                  final vm = vmsOf(context).reportSettings;
                  if (await runStep(context, () => vm.resetSchool(schoolId), done: 'School settings removed.', where: 'ReportSettings')) {
                    setState(() => _reload++);
                  }
                },
              ),
          ]);
        },
      ),
    );
  }
}
