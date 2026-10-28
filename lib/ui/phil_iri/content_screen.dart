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
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passages and questions'),
        actions: [
          if (canEdit && wide)
            mainActionButton(onPressed: () => _after(editor.addCollection(context)), icon: Icons.add, label: 'Add collection'),
        ],
      ),
      floatingActionButton: canEdit && !wide
          ? mainActionFab(onPressed: () => _after(editor.addCollection(context)), icon: Icons.add, label: 'Add collection')
          : null,
      body: LoadView<List<PhilIriCollection>>(
        where: 'PhilIriContent',
        reloadKey: _reload,
        load: (vms) async {
          await vms.philIriContent.loadCollections();
          return List.of(vms.philIriContent.collections);
        },
        builder: (context, items, _) {
          final colors = Theme.of(context).colorScheme;
          return PageBody(
            children: [
              if (items.isEmpty)
                const EmptyNote('No collections on this device. Download the latest data first.', icon: Icons.collections_bookmark_outlined),
              if (items.isNotEmpty) ...[
                StatGrid(tileWidth: 170, tiles: [
                  StatTile(label: 'Collections', value: '${items.length}', icon: Icons.collections_bookmark_outlined),
                  StatTile(label: 'Active', value: '${items.where((c) => c.isActive).length}', icon: Icons.check_circle_outline),
                  StatTile(label: 'Region-wide', value: '${items.where((c) => c.schoolId == null).length}', icon: Icons.public),
                  StatTile(label: 'DepEd-prescribed', value: '${items.where((c) => c.isPrescribed).length}', icon: Icons.verified_outlined),
                ]),
                const SizedBox(height: 4),
                ListCard(
                  title: 'Collections',
                  children: [
                    for (final c in items)
                      ListRow(
                        leading: c.isActive
                            ? const IconBadge(Icons.collections_bookmark_outlined)
                            : IconBadge(Icons.visibility_off_outlined, background: colors.surfaceContainerHighest, foreground: colors.onSurfaceVariant),
                        title: c.name,
                        subtitle: [
                          c.schoolId == null ? 'Region-wide' : 'School #${c.schoolId}',
                          ?c.description,
                        ].join(' · '),
                        footer: c.isPrescribed || !c.isActive
                            ? Wrap(spacing: 6, runSpacing: 6, children: [
                                if (c.isPrescribed) const StatusChip('DepEd-prescribed', tone: StatusTone.good, icon: Icons.verified_outlined),
                                if (!c.isActive) const StatusChip('inactive', tone: StatusTone.bad),
                              ])
                            : null,
                        trailing: const [Icon(Icons.chevron_right)],
                        onTap: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => _CollectionScreen(collection: c, editor: canEdit ? editor : null)));
                          if (mounted) setState(() => _reload++);
                        },
                      ),
                  ],
                ),
              ],
              if (canEdit && !wide) const SizedBox(height: 72),
            ],
          );
        },
      ),
    );
  }
}

/// A tonal "Add" for a card header.
Widget _addButton(VoidCallback onPressed) =>
    FilledButton.tonalIcon(onPressed: onPressed, icon: const Icon(Icons.add), label: const Text('Add'));

/// A row's ⋮ menu holding its one destructive action.
Widget _deleteMenu(VoidCallback onDelete) => PopupMenuButton<String>(
  onSelected: (_) => onDelete(),
  itemBuilder: (_) => const [
    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
  ],
);

/// Two columns from 1000 px ([left] wider), else one.
Widget _twoColumns(List<Widget> left, List<Widget> right) => LayoutBuilder(builder: (context, c) {
  List<Widget> spaced(List<Widget> l) => [for (var i = 0; i < l.length; i++) ...[if (i > 0) const SizedBox(height: 16), l[i]]];
  if (c.maxWidth < 1000) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([...left, ...right]));
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(left))),
    const SizedBox(width: 16),
    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(right))),
  ]);
});

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
          final colors = Theme.of(context).colorScheme;
          final rubric = ListCard(
            title: 'Rubric',
            trailing: editor == null ? null : _addButton(() => _after(editor.addCriterion(context, c))),
            children: [
              if (criteria.isEmpty) const EmptyNote('No rubric criteria.', icon: Icons.rule),
              for (final k in criteria)
                ListRow(
                  leading: LetterBadge('${k.criterionNo}', size: 36),
                  title: '${k.criterionNo}. ${k.name}',
                  subtitle: '${k.scaleMin} to ${k.scaleMax}',
                  trailing: [if (editor != null) _deleteMenu(() => _after(editor.deleteCriterion(context, k)))],
                ),
            ],
          );
          final passageList = ListCard(
            title: 'Passages (${passages.length})',
            trailing: editor == null ? null : _addButton(() => _after(editor.addPassage(context, c))),
            children: [
              if (passages.isEmpty) const EmptyNote('No passages.', icon: Icons.auto_stories_outlined),
              for (final p in passages)
                ListRow(
                  leading: p.level != null
                      ? LetterBadge(
                          'G${p.level}',
                          background: p.isActive ? null : colors.surfaceContainerHighest,
                          foreground: p.isActive ? null : colors.onSurfaceVariant,
                        )
                      : IconBadge(
                          Icons.menu_book_outlined,
                          background: p.isActive ? null : colors.surfaceContainerHighest,
                          foreground: p.isActive ? null : colors.onSurfaceVariant,
                        ),
                  title: p.title,
                  subtitle: [
                    if (p.level != null) 'Grade ${p.level}',
                    if (p.setCode != null) 'Set ${p.setCode}',
                    ?p.testType,
                    '${p.wordCount} words',
                  ].join(' · '),
                  trailing: [
                    if (!p.isActive) const StatusChip('inactive', tone: StatusTone.bad),
                    const Icon(Icons.chevron_right),
                  ],
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PassageScreen(passage: p, editor: editor)));
                    if (mounted) setState(() => _reload++);
                  },
                ),
            ],
          );
          return PageBody(
            maxWidth: 1200,
            children: [
              StatGrid(tileWidth: 170, tiles: [
                StatTile(label: 'Passages', value: '${passages.length}', icon: Icons.auto_stories_outlined),
                StatTile(label: 'Active passages', value: '${passages.where((p) => p.isActive).length}', icon: Icons.check_circle_outline),
                StatTile(label: 'Rubric criteria', value: '${criteria.length}', icon: Icons.rule),
                StatTile(label: 'Total words', value: '${passages.fold<int>(0, (n, p) => n + p.wordCount)}', icon: Icons.notes),
              ]),
              _twoColumns([passageList], [rubric]),
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
        builder: (context, questions, _) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final text = SectionCard(
            title: 'Text',
            icon: Icons.menu_book_outlined,
            trailing: p.isActive ? null : const StatusChip('inactive', tone: StatusTone.bad),
            children: [
              if (p.motivation != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: colors.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p.motivation!,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSecondaryContainer, fontStyle: FontStyle.italic)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              SelectableText(p.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
            ],
          );
          final questionList = ListCard(
            title: 'Questions',
            trailing: editor == null ? null : _addButton(() => _after(editor.addQuestion(context, p))),
            children: [
              if (questions.isEmpty) const EmptyNote('No questions.', icon: Icons.quiz_outlined),
              for (final q in questions)
                _QuestionRow(question: q, onDelete: editor == null ? null : () => _after(editor.deleteQuestion(context, q))),
            ],
          );
          return PageBody(
            maxWidth: 1200,
            children: [
              StatGrid(tileWidth: 150, tiles: [
                StatTile(label: 'Words', value: '${p.wordCount}', icon: Icons.notes),
                StatTile(label: 'Questions', value: '${questions.length}', icon: Icons.quiz_outlined),
                StatTile(label: 'Grade', value: p.level == null ? '—' : '${p.level}', icon: Icons.school_outlined),
                StatTile(label: 'Set', value: p.setCode ?? '—', icon: Icons.layers_outlined),
              ]),
              if (!p.wordCountMatches)
                NoticeBanner('Note: the text has ${p.words.length} words; the count says ${p.wordCount}.', icon: Icons.warning_amber_outlined),
              _twoColumns([text], [questionList]),
            ],
          );
        },
      ),
    );
  }
}

/// A question: number badge, prompt, its choices (the key ticked) and chips.
class _QuestionRow extends StatelessWidget {
  final PhilIriQuestion question;
  final VoidCallback? onDelete;
  const _QuestionRow({required this.question, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final q = question;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LetterBadge('${q.questionNo}', size: 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${q.questionNo}. ${q.prompt}', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (var i = 0; i < q.choices.length; i++)
              Builder(builder: (context) {
                final letter = String.fromCharCode(97 + i);
                final key = letter == q.answerKey;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(key ? Icons.check_circle : Icons.circle_outlined, size: 16, color: key ? colors.tertiary : colors.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$letter. ${q.choices[i]}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: key ? colors.onSurface : colors.onSurfaceVariant,
                          fontWeight: key ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ]),
                );
              }),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusChip('Answer: ${q.answerKey}', tone: StatusTone.good),
              if (q.questionType != null) StatusChip(q.questionType!.name),
            ]),
          ]),
        ),
        if (onDelete != null) ...[const SizedBox(width: 8), _deleteMenu(onDelete!)],
      ]),
    );
  }
}
