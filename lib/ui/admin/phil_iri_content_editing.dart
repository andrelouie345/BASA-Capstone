// lib/ui/admin/phil_iri_content_editing.dart
// The Phil-IRI content screen's admin part: add collections, rubric
// criteria, passages and questions; turn a collection or passage on or
// off, promote or delete it. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_collection.dart';
import '../../core/models/phil_iri_passage.dart';
import '../../core/models/phil_iri_question.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../phil_iri/content_screen.dart';

class AdminPhilIriContentEditor extends PhilIriContentEditor {
  const AdminPhilIriContentEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  void _warn(BuildContext context) {
    final w = vmsOf(context).philIriContent.lastMirrorWarning;
    if (w != null && context.mounted) showNote(context, w);
  }

  @override
  Future<bool> addCollection(BuildContext context) async {
    final vm = vmsOf(context).philIriContent;
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final f = await askFields(context, title: 'Add collection', fields: const [
      FieldSpec('name', 'Name'),
      FieldSpec('desc', 'Description', optional: true, multiline: true),
      FieldSpec('graded', 'Passages carry a grade level (yes/no)', initial: 'yes'),
      FieldSpec('comp', 'Passages have comprehension questions (yes/no)', initial: 'yes'),
    ]);
    if (f == null || !context.mounted) return false;
    final made = await runAction(
      context,
      () => vm.createCollection(
        schoolId: schoolId,
        name: f['name']!,
        description: f['desc']!.isEmpty ? null : f['desc'],
        isGradeLeveled: f['graded']!.toLowerCase().startsWith('y'),
        hasComprehension: f['comp']!.toLowerCase().startsWith('y'),
      ),
      done: 'Collection added.',
      where: 'PhilIriContent',
    );
    if (context.mounted) _warn(context);
    return made != null;
  }

  /// True when the collection is gone (the caller closes its page).
  @override
  Future<bool> collectionAction(BuildContext context, PhilIriCollection c) async {
    final vm = vmsOf(context).philIriContent;
    final a = await _pickAction(
      context,
      title: c.name,
      options: [c.isActive ? 'off' : 'on', if (c.schoolId != null) 'promote', 'delete'],
      label: (a) => switch (a) {
        'off' => 'Turn off',
        'on' => 'Turn on',
        'promote' => 'Make region-wide',
        _ => 'Delete',
      },
    );
    if (a == null || !context.mounted) return false;
    switch (a) {
      case 'off' || 'on':
        await runAction(context, () => vm.setCollectionActive(c.id!, a == 'on'), done: 'Saved.', where: 'PhilIriContent');
        return false;
      case 'promote':
        await runAction(context, () => vm.promoteCollection(c.id!), done: 'Collection is region-wide now.', where: 'PhilIriContent');
        return false;
      default:
        if (!await confirm(context, title: 'Delete ${c.name}?', action: 'Delete', destructive: true) || !context.mounted) return false;
        return runStep(context, () => vm.deleteCollection(c.id!), done: 'Collection deleted.', where: 'PhilIriContent');
    }
  }

  @override
  Future<bool> addCriterion(BuildContext context, PhilIriCollection c) async {
    final vm = vmsOf(context).philIriContent;
    final f = await askFields(context, title: 'Add rubric criterion', fields: const [
      FieldSpec('name', 'Name'),
      FieldSpec('min', 'Lowest score', initial: '1', number: true),
      FieldSpec('max', 'Highest score', number: true),
    ]);
    if (f == null || !context.mounted) return false;
    final min = int.tryParse(f['min']!), max = int.tryParse(f['max']!);
    if (min == null || max == null) {
      showNote(context, 'Scores must be whole numbers.');
      return false;
    }
    return await runAction(context, () => vm.addCriterion(collectionId: c.id!, name: f['name']!, scaleMin: min, scaleMax: max),
            done: 'Criterion added.', where: 'PhilIriContent') !=
        null;
  }

  @override
  Future<bool> deleteCriterion(BuildContext context, PhilIriRubricCriterion k) async {
    if (!await confirm(context, title: 'Delete ${k.name}?', action: 'Delete', destructive: true) || !context.mounted) return false;
    final vm = vmsOf(context).philIriContent;
    return runStep(context, () => vm.deleteCriterion(k.collectionId, k.id!), done: 'Criterion deleted.', where: 'PhilIriContent');
  }

  @override
  Future<bool> addPassage(BuildContext context, PhilIriCollection c) async {
    final vm = vmsOf(context).philIriContent;
    final f = await askFields(context, title: 'Add passage', fields: const [
      FieldSpec('title', 'Title'),
      FieldSpec('level', 'Grade level', number: true, optional: true),
      FieldSpec('set', 'Set (A to D)', optional: true),
      FieldSpec('type', 'Test type (pre, mosy, post; empty = any round)', optional: true),
      FieldSpec('motivation', 'Motivation question', optional: true),
      FieldSpec('body', 'Text (paragraphs on separate lines)', multiline: true),
      FieldSpec('words', 'Number of words', number: true, optional: true),
    ]);
    if (f == null || !context.mounted) return false;
    String? opt(String k) => f[k]!.isEmpty ? null : f[k];
    final body = f['body']!;
    final words = int.tryParse(f['words']!) ?? body.trim().split(RegExp(r'\s+')).length;
    final made = await runAction(
      context,
      () => vm.addPassage(PhilIriPassage(
        collectionId: c.id!,
        title: f['title']!,
        level: int.tryParse(f['level']!),
        setCode: opt('set'),
        testType: opt('type'),
        motivation: opt('motivation'),
        body: body,
        wordCount: words,
      )),
      done: 'Passage added.',
      where: 'PhilIriContent',
    );
    if (context.mounted) _warn(context);
    return made != null;
  }

  @override
  Future<bool> passageAction(BuildContext context, PhilIriPassage p) async {
    final vm = vmsOf(context).philIriContent;
    final a = await _pickAction(
      context,
      title: p.title,
      options: [p.isActive ? 'off' : 'on', 'delete'],
      label: (a) => switch (a) {
        'off' => 'Turn off',
        'on' => 'Turn on',
        _ => 'Delete',
      },
    );
    if (a == null || !context.mounted) return false;
    if (a != 'delete') {
      await runAction(context, () => vm.setPassageActive(p.id!, a == 'on'), done: 'Saved.', where: 'PhilIriContent');
      return false;
    }
    if (!await confirm(context, title: 'Delete ${p.title}?', action: 'Delete', destructive: true) || !context.mounted) return false;
    return runStep(context, () => vm.deletePassage(p.id!), done: 'Passage deleted.', where: 'PhilIriContent');
  }

  @override
  Future<bool> addQuestion(BuildContext context, PhilIriPassage p) async {
    final vm = vmsOf(context).philIriContent;
    final f = await askFields(context, title: 'Add question', fields: const [
      FieldSpec('prompt', 'Question', multiline: true),
      FieldSpec('choices', 'Choices, one per line (a, b, c, ...)', multiline: true),
      FieldSpec('key', 'Answer letter (e.g. b)'),
      FieldSpec('type', 'Type: L, I or C', optional: true),
    ]);
    if (f == null || !context.mounted) return false;
    final choices = f['choices']!.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final type = PhilIriQuestionType.values.where((t) => t.code == f['type']!.toUpperCase()).firstOrNull;
    return await runAction(
          context,
          () => vm.addQuestion(passageId: p.id!, prompt: f['prompt']!, choices: choices, answerKey: f['key']!.toLowerCase(), questionType: type),
          done: 'Question added.',
          where: 'PhilIriContent',
        ) !=
        null;
  }

  @override
  Future<bool> deleteQuestion(BuildContext context, PhilIriQuestion q) async {
    if (!await confirm(context, title: 'Delete question ${q.questionNo}?', action: 'Delete', destructive: true) || !context.mounted) {
      return false;
    }
    final vm = vmsOf(context).philIriContent;
    return runStep(context, () => vm.deleteQuestion(q.passageId, q.id!), done: 'Question deleted.', where: 'PhilIriContent');
  }
}

/// Picks one of a collection's or passage's actions ('on', 'off', 'promote',
/// 'delete'): each with its icon, Delete in the error colour. Null when cancelled.
Future<String?> _pickAction(BuildContext context,
    {required String title, required List<String> options, required String Function(String) label}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            Builder(builder: (context) {
              final delete = o == 'delete';
              final icon = switch (o) {
                'off' => Icons.visibility_off_outlined,
                'on' => Icons.visibility_outlined,
                'promote' => Icons.public,
                _ => Icons.delete_outline,
              };
              return SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(o),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(children: [
                  Icon(icon, size: 20, color: delete ? colors.error : colors.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(child: Text(label(o), style: delete ? TextStyle(color: colors.error) : null)),
                ]),
              );
            }),
        ],
      );
    },
  );
}
