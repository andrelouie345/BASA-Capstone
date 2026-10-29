// lib/ui/aral/materials_screen.dart
// Materials (docs/handoff/screens/aral.md, Materials and recommendations):
// the ARAL learning-material catalog (file names and links, no files).
// A learner's recommendations are on their ARAL page. Changing the catalog
// is admin-only: the admin build passes an [AralMaterialsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/aral_material.dart';
import '../common/screen_kit.dart';

/// The admin build's catalog changes. Each returns true when something changed.
abstract class AralMaterialsEditor {
  const AralMaterialsEditor();
  bool canEdit(BuildContext context);
  Future<bool> add(BuildContext context);
  Future<bool> actions(BuildContext context, AralMaterial m);
}

class AralMaterialsScreen extends StatefulWidget {
  final AralMaterialsEditor? editor;
  const AralMaterialsScreen({super.key, this.editor});

  @override
  State<AralMaterialsScreen> createState() => _AralMaterialsScreenState();
}

class _AralMaterialsScreenState extends State<AralMaterialsScreen> {
  int _reload = 0;
  String _filter = '';

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    final wide = isWideScreen(context);
    void add() => _after(editor!.add(context));
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARAL materials'),
        actions: [if (canEdit && wide) mainActionButton(onPressed: add, icon: Icons.add, label: 'Add material')],
      ),
      floatingActionButton: canEdit && !wide ? mainActionFab(onPressed: add, icon: Icons.add, label: 'Add material') : null,
      body: LoadView<List<AralMaterial>>(
        where: 'AralMaterials',
        reloadKey: _reload,
        load: (vms) => vms.aralMaterial.catalog(),
        builder: (context, items, _) {
          final shown = items.where((m) => _filter.isEmpty || m.title.toLowerCase().contains(_filter)).toList();
          final colors = Theme.of(context).colorScheme;
          return PageBody(children: [
            FilterBar(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search title'),
                onChanged: (v) => setState(() => _filter = v.toLowerCase()),
              ),
            ]),
            if (items.isEmpty)
              const EmptyNote('No materials in the catalog yet.', icon: Icons.menu_book_outlined)
            else ...[
              StatGrid(tiles: [
                StatTile(label: 'Materials', value: '${items.length}', icon: Icons.menu_book_outlined),
                StatTile(label: 'Active', value: '${items.where((m) => m.isActive).length}', icon: Icons.visibility_outlined),
                StatTile(label: 'Region-wide', value: '${items.where((m) => m.schoolId == null).length}', icon: Icons.public),
              ]),
              if (shown.isEmpty)
                const EmptyNote('No material matches the search.', icon: Icons.search_off)
              else
                ListCard(children: [
                  for (final m in shown)
                    ListRow(
                      leading: IconBadge(
                        m.isActive ? Icons.menu_book_outlined : Icons.visibility_off_outlined,
                        background: m.isActive ? null : colors.surfaceContainerHigh,
                        foreground: m.isActive ? null : colors.onSurfaceVariant,
                      ),
                      title: m.title,
                      subtitle: [
                        m.track == null ? m.keyStage.label : '${m.keyStage.label} ${m.track!.label}',
                        m.kind.label,
                        m.language,
                        'Grades ${m.minGrade}–${m.maxGrade}',
                        m.schoolId == null ? 'region-wide' : 'school #${m.schoolId}',
                        ?m.fileName,
                        if (!m.isActive) 'inactive',
                      ].join(' · '),
                      footer: m.isActive ? null : const StatusChip('INACTIVE'),
                      onTap: m.link == null ? null : () => showTextDialog(context, title: m.title, text: m.link!),
                      trailing: [
                        if (m.link != null) Icon(Icons.link, size: 20, color: colors.onSurfaceVariant),
                        if (canEdit) IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _after(editor.actions(context, m))),
                      ],
                    ),
                ]),
            ],
            // Room for the floating button.
            if (canEdit && !wide) const SizedBox(height: 72),
          ]);
        },
      ),
    );
  }
}
