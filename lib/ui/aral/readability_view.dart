// lib/ui/aral/readability_view.dart
// Readability log (docs/handoff/screens/aral.md, SHARP only): the texts a
// learner read with their Flesch reading ease and grade, added from word,
// sentence and syllable counts. Shown only while the school has SHARP on.
import 'package:flutter/material.dart';

import '../../viewmodels/aral_readability_viewmodel.dart';
import '../common/screen_kit.dart';
import 'aral_common.dart';

class ReadabilityView extends StatefulWidget {
  final int enrollmentId;
  const ReadabilityView({super.key, required this.enrollmentId});

  @override
  State<ReadabilityView> createState() => _ReadabilityViewState();
}

class _ReadabilityViewState extends State<ReadabilityView> {
  int _reload = 0;

  Future<void> _edit([AralReadabilityEntry? e]) async {
    final l = e?.log;
    final f = await askFields(context, title: e == null ? 'Add a text' : 'Edit text', fields: [
      FieldSpec('title', 'Title', initial: l?.title ?? '', optional: true),
      FieldSpec('words', 'Words', initial: l?.words.toString() ?? '', number: true),
      FieldSpec('sentences', 'Sentences', initial: l?.sentences.toString() ?? '', number: true),
      FieldSpec('syllables', 'Syllables', initial: l?.syllables.toString() ?? '', number: true),
      FieldSpec('source', 'Source (link or reference)', initial: l?.source ?? '', optional: true),
    ]);
    if (f == null || !mounted) return;
    final w = int.tryParse(f['words']!), s = int.tryParse(f['sentences']!), y = int.tryParse(f['syllables']!);
    if (w == null || s == null || y == null) return showNote(context, 'Counts must be whole numbers.');
    final vm = vmsOf(context).aralReadability;
    final source = f['source']!.isEmpty ? null : f['source'];
    final title = f['title']!.isEmpty ? null : f['title'];
    await runAction(
      context,
      () => e == null
          ? vm.add(enrollmentId: widget.enrollmentId, title: title, words: w, sentences: s, syllables: y, source: source)
          : vm.update(e.log.id!, title: title, words: w, sentences: s, syllables: y, source: () => source),
      done: 'Saved.',
      where: 'Readability',
    );
    setState(() => _reload++);
  }

  Future<void> _delete(AralReadabilityEntry e) async {
    if (!await confirm(context, title: 'Delete ${e.log.title}?', action: 'Delete', destructive: true) || !mounted) return;
    final vm = vmsOf(context).aralReadability;
    await runStep(context, () => vm.delete(e.log.id!), where: 'Readability');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = mySchoolId(context);
    if (schoolId == null) return const NeedsSchoolNote();
    return LoadView<(bool, List<AralReadabilityEntry>)>(
      where: 'Readability',
      reloadKey: _reload,
      load: (vms) async {
        final on = await vms.aralReadability.available(schoolId);
        return (on, on ? await vms.aralReadability.entries(widget.enrollmentId) : <AralReadabilityEntry>[]);
      },
      builder: (context, data, _) {
        final (on, entries) = data;
        if (!on) return const EmptyNote('The readability log is kept only while the school runs SHARP.');
        return PageBody(
          children: [
            FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Add a text')),
            if (entries.isEmpty) const EmptyNote('No texts logged yet.'),
            for (final e in entries)
              Card(
                child: ListTile(
                  title: Text(e.log.title),
                  subtitle: Text('${e.log.readOn} · ease ${e.readability.readingEase.toStringAsFixed(1)} · '
                      'grade ${e.readability.gradeLevel.toStringAsFixed(1)}'
                      '${e.log.source == null ? '' : '\n${e.log.source}'}'),
                  onTap: () => _edit(e),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(e)),
                ),
              ),
          ],
        );
      },
    );
  }
}
