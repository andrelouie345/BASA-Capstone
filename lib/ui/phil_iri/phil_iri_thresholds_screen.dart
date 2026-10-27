// lib/ui/phil_iri/phil_iri_thresholds_screen.dart
// Phil-IRI thresholds (docs/handoff/screens/phil-iri.md): the cut-offs in
// force for the user's school and where each comes from (school, region or
// the built-in default). Changing them is admin-only: the admin build
// passes a [PhilIriThresholdsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../viewmodels/phil_iri_content_viewmodel.dart';
import '../common/screen_kit.dart';
import '../crla/crla_thresholds_screen.dart';

/// The admin build's threshold changes. Returns true when something changed.
abstract class PhilIriThresholdsEditor {
  const PhilIriThresholdsEditor();
  bool canEdit(BuildContext context);
  Future<bool> edit(BuildContext context, int? schoolId, PhilIriThresholdLayers layers);
  Future<bool> reset(BuildContext context, int schoolId);
}

class PhilIriThresholdsScreen extends StatefulWidget {
  final PhilIriThresholdsEditor? editor;
  const PhilIriThresholdsScreen({super.key, this.editor});

  @override
  State<PhilIriThresholdsScreen> createState() => _PhilIriThresholdsScreenState();
}

class _PhilIriThresholdsScreenState extends State<PhilIriThresholdsScreen> {
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
      appBar: AppBar(title: const Text('Phil-IRI thresholds')),
      body: LoadView<PhilIriThresholdLayers>(
        where: 'PhilIriThresholds',
        reloadKey: _reload,
        load: (vms) => vms.philIriContent.thresholdLayers(schoolId),
        builder: (context, layers, _) {
          final school = layers.school?.settings ?? const {};
          final region = layers.region?.settings ?? const {};
          String show(Object? v) => v is List ? v.join(', ') : '$v';
          return PageBody(
            children: [
              Text(schoolId == null ? 'Region defaults.' : 'In force at your school.'),
              if (canEdit)
                Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => _after(editor.edit(context, schoolId, layers)),
                    icon: const Icon(Icons.edit),
                    label: const Text('Change'),
                  ),
                  if (schoolId != null && school.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _after(editor.reset(context, schoolId)),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text("Use the region's values"),
                    ),
                ]),
              SectionCard(
                title: 'Cut-offs',
                children: [
                  for (final e in layers.effective.toMap().entries)
                    InfoRow(
                      thresholdLabel(e.key),
                      '${show(e.value)}  (${school.containsKey(e.key) ? 'school' : region.containsKey(e.key) ? 'region' : 'default'})',
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
