// lib/ui/learners/sections_screen.dart
// Sections (docs/handoff/screens/admin.md, Sections): the sections on this
// device by school year and grade. Adding, editing and deleting are
// admin-only: the admin build passes a [SectionsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../common/screen_kit.dart';

/// The admin build's section changes. Each returns true when something changed.
abstract class SectionsEditor {
  const SectionsEditor();
  bool canEdit(BuildContext context);
  Future<bool> add(BuildContext context);
  Future<bool> edit(BuildContext context, Section section);
  Future<bool> delete(BuildContext context, Section section);
}

class SectionsScreen extends StatefulWidget {
  final SectionsEditor? editor;
  const SectionsScreen({super.key, this.editor});

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends State<SectionsScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sections')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _after(editor.add(context)),
              icon: const Icon(Icons.add),
              label: const Text('Add section'),
            )
          : null,
      body: LoadView<List<Section>>(
        where: 'SectionsScreen',
        reloadKey: _reload,
        load: (vms) => vms.section.localSections(),
        builder: (context, items, _) {
          if (items.isEmpty) {
            return const EmptyNote('No sections on this device yet. Download the latest data first.');
          }
          final byYear = <String, List<Section>>{};
          for (final s in items) {
            byYear.putIfAbsent(s.schoolYear, () => []).add(s);
          }
          final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
          int grade(Section s) => int.tryParse(s.gradeLevel) ?? 0;
          return PageBody(
            children: [
              for (final y in years)
                SectionCard(
                  title: 'School year $y',
                  children: [
                    for (final s in byYear[y]!..sort((a, b) => grade(a).compareTo(grade(b))))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text(s.gradeLevel)),
                        title: Text(s.sectionName),
                        subtitle: Text('Grade ${s.gradeLevel} · school #${s.schoolId}'),
                        trailing: canEdit
                            ? PopupMenuButton<String>(
                                onSelected: (v) => _after(v == 'edit' ? editor.edit(context, s) : editor.delete(context, s)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
              const SizedBox(height: 72),
            ],
          );
        },
      ),
    );
  }
}
