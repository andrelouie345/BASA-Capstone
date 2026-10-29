// lib/ui/admin/reports_hub_screen.dart
// Reports & files (docs/handoff/screens/reports.md, hub): every import and
// export in one place. Each tile opens the screen that does the work. Admin
// build only.
import 'package:flutter/material.dart';

import '../common/screen_kit.dart';
import '../crla/crla_export_screen.dart';
import '../learners/learners_screen.dart';
import '../reports/srp_screen.dart';
import 'aral_report_screen.dart';
import 'crla_import_screen.dart';
import 'report_screens.dart';
import 'sf1_import_screen.dart';
import 'srp_editing.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String sub, WidgetBuilder open) => ListRow(
      leading: IconBadge(icon),
      title: title,
      subtitle: sub,
      trailing: const [Icon(Icons.chevron_right)],
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: open)),
    );
    final theme = Theme.of(context);
    Widget head(String s, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(s, style: theme.textTheme.titleMedium),
      ]),
    );
    final imports = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head('Import', Icons.file_upload_outlined),
      ListCard(children: [
        tile(Icons.upload_file, 'SF1 workbook', 'Learners of a section', (_) => const Sf1ImportScreen()),
        tile(Icons.file_upload_outlined, 'CRLA scoresheet', 'A filled CRLA2 scoresheet', (_) => const CrlaImportScreen()),
        tile(Icons.group_add_outlined, 'ARAL roster', 'Preview, then import', (_) => const AralReportScreen()),
      ]),
    ]);
    final exports = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head('Export', Icons.file_download_outlined),
      ListCard(children: [
        tile(Icons.people_outline, 'Section roster CSV', 'From the Learners screen', (_) => const LearnersScreen()),
        tile(Icons.file_download_outlined, 'CRLA scoresheet', 'Fill the CRLA2 template', (_) => const CrlaExportScreen()),
        tile(Icons.description_outlined, 'ARAL implementation report, roster, check-ins', 'Template or CSV', (_) => const AralReportScreen()),
        tile(Icons.assessment_outlined, 'NLA portal report', 'CSV', (_) => const NlaReportScreen()),
        tile(Icons.donut_large_outlined, 'Progress monitoring', 'CSV', (_) => const ProgressScreen()),
        tile(Icons.format_list_numbered, 'BOSY masterlist', 'CSV', (_) => const BosyMasterlistScreen()),
        tile(Icons.wb_sunny_outlined, 'SRP candidates and classes', 'CSV', (_) => const SrpScreen(editor: AdminSrpEditor())),
      ]),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & files')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 1000
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: imports),
                    const SizedBox(width: 16),
                    Expanded(child: exports),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [imports, const SizedBox(height: 16), exports]),
          ),
        ],
      ),
    );
  }
}
