// lib/ui/crla/crla_thresholds_screen.dart
// CRLA thresholds (docs/handoff/screens/crla.md): the cut-offs in force for
// the user's school and where each comes from (school, region or the
// built-in default). Changing them is admin-only: the admin build passes a
// [CrlaThresholdsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../viewmodels/crla_threshold_viewmodel.dart';
import '../common/screen_kit.dart';

/// The admin build's threshold changes. Returns true when something changed.
abstract class CrlaThresholdsEditor {
  const CrlaThresholdsEditor();
  bool canEdit(BuildContext context);
  Future<bool> edit(BuildContext context, int? schoolId, CrlaThresholdLayers layers);
  Future<bool> reset(BuildContext context, int schoolId);
}

class CrlaThresholdsScreen extends StatefulWidget {
  final CrlaThresholdsEditor? editor;
  const CrlaThresholdsScreen({super.key, this.editor});

  @override
  State<CrlaThresholdsScreen> createState() => _CrlaThresholdsScreenState();
}

class _CrlaThresholdsScreenState extends State<CrlaThresholdsScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CRLA thresholds')),
      body: LoadView<CrlaThresholdLayers>(
        where: 'CrlaThresholds',
        reloadKey: _reload,
        load: (vms) => vms.crlaThresholds.thresholdLayers(schoolId),
        builder: (context, layers, _) {
          final effective = layers.effective.toMap();
          final school = layers.school?.settings ?? const {};
          final region = layers.region?.settings ?? const {};
          return PageBody(
            children: [
              NoticeBanner(
                schoolId == null ? 'Region defaults.' : 'In force at your school.',
                icon: schoolId == null ? Icons.map_outlined : Icons.school_outlined,
                tone: StatusTone.neutral,
              ),
              if (canEdit)
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                    if (schoolId != null && school.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _after(editor.reset(context, schoolId)),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text("Use the region's values"),
                      ),
                    FilledButton.icon(
                      onPressed: () => _after(editor.edit(context, schoolId, layers)),
                      icon: const Icon(Icons.edit),
                      label: const Text('Change'),
                    ),
                  ]),
                ),
              ListCard(
                title: 'Cut-offs',
                children: [
                  for (final e in effective.entries)
                    ListRow(
                      leading: const IconBadge(Icons.tune, size: 36),
                      title: thresholdLabel(e.key),
                      trailing: [
                        Text('${e.value}', style: Theme.of(context).textTheme.titleMedium),
                        _sourceChip(school.containsKey(e.key)
                            ? 'school'
                            : region.containsKey(e.key)
                            ? 'region'
                            : 'default'),
                      ],
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Where a cut-off comes from, as a chip: school = good, region and default neutral.
Widget _sourceChip(String source) =>
    SizedBox(width: 64, child: Center(child: StatusChip(source, tone: source == 'school' ? StatusTone.good : StatusTone.neutral)));

/// "part1_std_full_max" → "Part1 std full max".
String thresholdLabel(String key) {
  final s = key.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
