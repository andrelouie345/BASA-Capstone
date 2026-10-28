// lib/ui/learners/schools_screen.dart
// Schools (docs/handoff/screens/admin.md, Schools): the schools this user may
// see. Adding, editing and deleting are admin-only: the admin build passes a
// [SchoolsEditor] (lib/ui/admin/), so the tutor build never contains them.
import 'package:flutter/material.dart';

import '../../core/models/region.dart';
import '../../core/models/school.dart';
import '../common/screen_kit.dart';

/// The admin build's school changes. Each returns true when something changed.
abstract class SchoolsEditor {
  const SchoolsEditor();

  /// Whether the signed-in user may change schools (superadmin).
  bool canEdit(BuildContext context);
  Future<bool> add(BuildContext context);
  Future<bool> edit(BuildContext context, School school);
  Future<bool> delete(BuildContext context, School school);
}

class SchoolsScreen extends StatefulWidget {
  final SchoolsEditor? editor;
  const SchoolsScreen({super.key, this.editor});

  @override
  State<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends State<SchoolsScreen> {
  int _reload = 0;

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
        title: const Text('Schools'),
        actions: [if (canEdit && wide) mainActionButton(onPressed: add, icon: Icons.add, label: 'Add school')],
      ),
      floatingActionButton: canEdit && !wide ? mainActionFab(onPressed: add, icon: Icons.add, label: 'Add school') : null,
      body: LoadView<List<School>>(
        where: 'SchoolsScreen',
        reloadKey: _reload,
        load: (vms) async {
          await vms.school.loadAll();
          return List.of(vms.school.items);
        },
        builder: (context, items, _) => PageBody(
          children: [
            if (items.isEmpty) const EmptyNote('No schools to show.', icon: Icons.school_outlined),
            if (items.isNotEmpty) ...[
              StatGrid(tileWidth: 180, tiles: [
                StatTile(label: 'Schools', value: '${items.length}', icon: Icons.school_outlined),
                StatTile(
                  label: 'Regions',
                  value: '${items.map((s) => s.regionId).whereType<int>().toSet().length}',
                  icon: Icons.map_outlined,
                ),
              ]),
              ListCard(
                children: [
                  for (final s in items)
                    ListRow(
                      leading: const IconBadge(Icons.school_outlined),
                      title: s.schoolName,
                      subtitle: [
                        'School ID ${s.schoolId}',
                        if (s.regionId != null) Region.byId(s.regionId!)?.name ?? 'Region ${s.regionId}',
                        ?s.division,
                      ].join(' · '),
                      trailing: [
                        if (canEdit)
                          PopupMenuButton<String>(
                            onSelected: (v) => _after(v == 'edit' ? editor.edit(context, s) : editor.delete(context, s)),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ],
            if (canEdit && !wide) const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}
