// lib/ui/phil_iri/content_screen.dart
// Phil-IRI content (docs/handoff/screens/phil-iri.md, Content): collections,
// their rubric and passages, and each passage's text and questions. Read in
// both builds; changing content is admin-only: the admin build passes a
// [PhilIriContentEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_collection.dart';
import '../../core/models/phil_iri_passage.dart';
import '../../core/models/phil_iri_question.dart';
import '../common/screen_kit.dart';

/// The admin build's content changes. Each returns true when something changed.
abstract class PhilIriContentEditor {
  const PhilIriContentEditor();
  bool canEdit(BuildContext context);
  Future<bool> addCollection(BuildContext context);
  Future<bool> collectionAction(BuildContext context, PhilIriCollection c);
  Future<bool> addCriterion(BuildContext context, PhilIriCollection c);
  Future<bool> deleteCriterion(BuildContext context, PhilIriRubricCriterion criterion);
  Future<bool> addPassage(BuildContext context, PhilIriCollection c);
  Future<bool> passageAction(BuildContext context, PhilIriPassage p);
  Future<bool> addQuestion(BuildContext context, PhilIriPassage p);
  Future<bool> deleteQuestion(BuildContext context, PhilIriQuestion q);
}

class PhilIriContentScreen extends StatefulWidget {
  final PhilIriContentEditor? editor;
  const PhilIriContentScreen({super.key, this.editor});

  @override
  State<PhilIriContentScreen> createState() => _PhilIriContentScreenState();
}

class _PhilIriContentScreenState extends State<PhilIriContentScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Passages and questions')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _after(editor.addCollection(context)),
              icon: const Icon(Icons.add),
              label: const Text('Add collection'),
            )
          : null,
      body: LoadView<List<PhilIriCollection>>(
        where: 'PhilIriContent',
        reloadKey: _reload,
        load: (vms) async {
          await vms.philIriContent.loadCollections();
          return List.of(vms.philIriContent.collections);
        },
        builder: (context, items, _) => PageBody(
          children: [
            if (items.isEmpty) const EmptyNote('No collections on this device. Download the latest data first.'),
            for (final c in items)
              Card(
                child: ListTile(
                  leading: Icon(c.isActive ? Icons.collections_bookmark_outlined : Icons.visibility_off_outlined),
                  title: Text(c.name),
                  subtitle: Text([
                    c.schoolId == null ? 'Region-wide' : 'School #${c.schoolId}',
                    if (c.isPrescribed) 'DepEd-prescribed',
                    if (!c.isActive) 'inactive',
                    ?c.description,
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => _CollectionScreen(collection: c, editor: canEdit ? editor : null)));
                    if (mounted) setState(() => _reload++);
                  },
                ),
              ),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}

class _CollectionScreen extends StatefulWidget {
  final PhilIriCollection collection;
  final PhilIriContentEditor? editor;
  const _CollectionScreen({required this.collection, this.editor});

  @override
  State<_CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<_CollectionScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    final editor = widget.editor;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          if (editor != null)
            IconButton(
              tooltip: 'Collection actions',
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await editor.collectionAction(context, c)) nav.pop();
              },
            ),
        ],
      ),
      body: LoadView<(List<PhilIriRubricCriterion>, List<PhilIriPassage>)>(
        where: 'PhilIriContent',
        reloadKey: _reload,
        load: (vms) async => (await vms.philIriContent.criteria(c.id!), await vms.philIriContent.passages(c.id!)),
        builder: (context, data, _) {
          final (criteria, passages) = data;
          return PageBody(
            children: [
              SectionCard(
                title: 'Rubric',
                trailing: editor == null ? null : IconButton(icon: const Icon(Icons.add), onPressed: () => _after(editor.addCriterion(context, c))),
                children: [
                  if (criteria.isEmpty) const Text('No rubric criteria.'),
                  for (final k in criteria)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${k.criterionNo}. ${k.name}'),
                      subtitle: Text('${k.scaleMin} to ${k.scaleMax}'),
                      trailing: editor == null
                          ? null
                          : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _after(editor.deleteCriterion(context, k))),
                    ),
                ],
              ),
              SectionCard(
                title: 'Passages (${passages.length})',
                trailing: editor == null ? null : IconButton(icon: const Icon(Icons.add), onPressed: () => _after(editor.addPassage(context, c))),
                children: [
                  if (passages.isEmpty) const Text('No passages.'),
                  for (final p in passages)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.title),
                      subtitle: Text([
                        if (p.level != null) 'Grade ${p.level}',
                        if (p.setCode != null) 'Set ${p.setCode}',
                        ?p.testType,
                        '${p.wordCount} words',
                        if (!p.isActive) 'inactive',
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PassageScreen(passage: p, editor: editor)));
                        if (mounted) setState(() => _reload++);
                      },
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

class _PassageScreen extends StatefulWidget {
  final PhilIriPassage passage;
  final PhilIriContentEditor? editor;
  const _PassageScreen({required this.passage, this.editor});

  @override
  State<_PassageScreen> createState() => _PassageScreenState();
}

class _PassageScreenState extends State<_PassageScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.passage;
    final editor = widget.editor;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.title),
        actions: [
          if (editor != null)
            IconButton(
              tooltip: 'Passage actions',
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await editor.passageAction(context, p)) nav.pop();
              },
            ),
        ],
      ),
      body: LoadView<List<PhilIriQuestion>>(
        where: 'PhilIriContent',
        reloadKey: _reload,
        load: (vms) => vms.philIriContent.questions(p.id!),
        builder: (context, questions, _) => PageBody(
          children: [
            SectionCard(
              title: 'Text',
              children: [
                if (p.motivation != null) Text(p.motivation!, style: Theme.of(context).textTheme.bodySmall),
                SelectableText(p.body),
                if (!p.wordCountMatches) Text('Note: the text has ${p.words.length} words; the count says ${p.wordCount}.'),
              ],
            ),
            SectionCard(
              title: 'Questions',
              trailing: editor == null ? null : IconButton(icon: const Icon(Icons.add), onPressed: () => _after(editor.addQuestion(context, p))),
              children: [
                if (questions.isEmpty) const Text('No questions.'),
                for (final q in questions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${q.questionNo}. ${q.prompt}'),
                    subtitle: Text([
                      for (var i = 0; i < q.choices.length; i++) '${String.fromCharCode(97 + i)}. ${q.choices[i]}',
                      'Answer: ${q.answerKey}${q.questionType == null ? '' : ' · ${q.questionType!.name}'}',
                    ].join('\n')),
                    trailing: editor == null
                        ? null
                        : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _after(editor.deleteQuestion(context, q))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
