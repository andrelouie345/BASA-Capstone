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

  /// The loaded layers, for the main action outside the loaded body.
  final _layers = ValueNotifier<PhilIriThresholdLayers?>(null);

  @override
  void dispose() {
    _layers.dispose();
    super.dispose();
  }

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  /// "Change" (admin build), once the layers are loaded.
  Widget _mainAction(int? schoolId, {required bool fab}) => ValueListenableBuilder<PhilIriThresholdLayers?>(
    valueListenable: _layers,
    builder: (context, layers, _) {
      final editor = widget.editor;
      if (layers == null || editor == null || !editor.canEdit(context)) return const SizedBox.shrink();
      void go() => _after(editor.edit(context, schoolId, layers));
      return fab
          ? mainActionFab(onPressed: go, icon: Icons.edit, label: 'Change')
          : mainActionButton(onPressed: go, icon: Icons.edit, label: 'Change');
    },
  );

  @override
  Widget build(BuildContext context) {
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI thresholds'), actions: [if (wide) _mainAction(schoolId, fab: false)]),
      floatingActionButton: wide ? null : _mainAction(schoolId, fab: true),
      body: LoadView<PhilIriThresholdLayers>(
        where: 'PhilIriThresholds',
        reloadKey: _reload,
        load: (vms) => vms.philIriContent.thresholdLayers(schoolId),
        builder: (context, layers, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _layers.value = layers;
          });
          final school = layers.school?.settings ?? const {};
          final region = layers.region?.settings ?? const {};
          String show(Object? v) => v is List ? v.join(', ') : '$v';
          final entries = layers.effective.toMap().entries.toList();
          String source(String key) => school.containsKey(key) ? 'school' : region.containsKey(key) ? 'region' : 'default';
          int count(String s) => entries.where((e) => source(e.key) == s).length;
          return PageBody(
            children: [
              NoticeBanner(
                schoolId == null ? 'Region defaults.' : 'In force at your school.',
                icon: Icons.tune,
                tone: StatusTone.neutral,
              ),
              StatGrid(tileWidth: 160, tiles: [
                StatTile(label: 'From the school', value: '${count('school')}', icon: Icons.school_outlined),
                StatTile(label: 'From the region', value: '${count('region')}', icon: Icons.map_outlined),
                StatTile(label: 'Built-in defaults', value: '${count('default')}', icon: Icons.settings_suggest_outlined),
              ]),
              if (entries.isEmpty) const EmptyNote('No cut-offs to show.', icon: Icons.tune),
              if (entries.isNotEmpty)
                ListCard(
                  title: 'Cut-offs',
                  trailing: canEdit && schoolId != null && school.isNotEmpty
                      ? FilledButton.tonalIcon(
                          onPressed: () => _after(editor.reset(context, schoolId)),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text("Use the region's values"),
                        )
                      : null,
                  children: [
                    for (final e in entries)
                      ListRow(
                        leading: const IconBadge(Icons.straighten, size: 36),
                        title: thresholdLabel(e.key),
                        subtitle: '${show(e.value)}  (${source(e.key)})',
                        trailing: [
                          StatusChip(
                            source(e.key),
                            tone: switch (source(e.key)) {
                              'school' => StatusTone.good,
                              'region' => StatusTone.warn,
                              _ => StatusTone.neutral,
                            },
                          ),
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
