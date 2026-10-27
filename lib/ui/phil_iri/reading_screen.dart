// lib/ui/phil_iri/reading_screen.dart
// One passage reading of a Phil-IRI session: its timing, miscues marked on
// the passage's words (tap a word), observations, the comprehension answers,
// and the result computed from what is saved (after every save).
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_answer.dart';
import '../../core/models/phil_iri_miscue.dart';
import '../../core/models/phil_iri_passage.dart';
import '../../core/models/phil_iri_question.dart';
import '../../core/models/phil_iri_reading.dart';
import '../../core/models/phil_iri_types.dart';
import '../common/screen_kit.dart';
import 'session_screen.dart';

class PhilIriReadingScreen extends StatefulWidget {
  final int assessmentId;
  final int readingId;
  const PhilIriReadingScreen({super.key, required this.assessmentId, required this.readingId});

  @override
  State<PhilIriReadingScreen> createState() => _PhilIriReadingScreenState();
}

class _ReadingData {
  final PhilIriReading reading;
  final PhilIriPassage passage;
  final List<PhilIriMiscue> miscues;
  final List<PhilIriQuestion> questions;
  final List<PhilIriAnswer> answers;
  final PhilIriPassageResult? result;
  final String? resultNote;
  const _ReadingData(this.reading, this.passage, this.miscues, this.questions, this.answers, this.result, this.resultNote);
}

class _PhilIriReadingScreenState extends State<PhilIriReadingScreen> {
  int _reload = 0;
  void _again() => setState(() => _reload++);

  Future<void> _timing(PhilIriReading r) async {
    final oneMinute = r.method == PhilIriReadingMethod.oneMinute;
    final f = await askFields(context,
        title: oneMinute ? 'Words read in one minute' : 'Reading time',
        fields: [
          oneMinute
              ? FieldSpec('v', 'Words read', initial: r.wordsRead?.toString() ?? '', number: true)
              : FieldSpec('v', 'Seconds', initial: r.readingSeconds?.toString() ?? '', number: true),
        ]);
    final v = int.tryParse(f?['v'] ?? '');
    if (v == null || !mounted) return;
    final vm = vmsOf(context).philIri;
    await runAction(
      context,
      () => oneMinute ? vm.saveTiming(r.id!, wordsRead: v) : vm.saveTiming(r.id!, readingSeconds: v),
      done: 'Timing saved.',
      where: 'PhilIriReading',
    );
    _again();
  }

  Future<void> _word(int index, String word, PhilIriMiscue? existing) async {
    final r = await showDialog<_MiscueChoice>(context: context, builder: (_) => _MiscueDialog(word: word, existing: existing));
    if (r == null || !mounted) return;
    final vm = vmsOf(context).philIri;
    if (r.remove) {
      await runAction(context, () => vm.removeMiscue(existing!.id!), where: 'PhilIriReading');
    } else if (existing != null) {
      await runAction(
        context,
        () => vm.updateMiscue(PhilIriMiscue(
          id: existing.id,
          readingId: existing.readingId,
          wordIndex: existing.wordIndex,
          type: r.type!,
          spokenText: r.spoken,
          selfCorrected: r.selfCorrected,
        )),
        where: 'PhilIriReading',
      );
    } else {
      await runAction(
        context,
        () => vm.markMiscue(readingId: widget.readingId, wordIndex: index, type: r.type!, spokenText: r.spoken, selfCorrected: r.selfCorrected),
        where: 'PhilIriReading',
      );
    }
    _again();
  }

  Future<void> _observe(PhilIriObservation o) async {
    final vm = vmsOf(context).philIri;
    await runAction(context, () => vm.saveObservation(widget.readingId, o), where: 'PhilIriReading');
    _again();
  }

  Future<void> _answer(PhilIriQuestion q, String? chosen, bool lookedBack) async {
    final vm = vmsOf(context).philIri;
    await runAction(context, () => vm.answer(readingId: widget.readingId, questionId: q.id!, chosen: chosen, lookedBack: lookedBack),
        where: 'PhilIriReading');
    _again();
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: 'Delete this reading?', body: 'Its miscues and answers are deleted too.', action: 'Delete', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final vm = vmsOf(context).philIri;
    final nav = Navigator.of(context);
    if (await runStep(context, () => vm.deleteReading(widget.readingId), done: 'Reading deleted.', where: 'PhilIriReading')) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading'),
        actions: [IconButton(tooltip: 'Delete reading', onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: LoadView<_ReadingData?>(
        where: 'PhilIriReading',
        reloadKey: _reload,
        load: (vms) async {
          final vm = vms.philIri;
          final reading = (await vm.readings(widget.assessmentId)).where((r) => r.id == widget.readingId).firstOrNull;
          if (reading == null) return null;
          final passage = await vm.passage(reading.passageId);
          if (passage == null) return null;
          PhilIriPassageResult? result;
          String? note;
          if (reading.isTimed) {
            try {
              result = await vm.scoreReading(reading.id!);
            } catch (e) {
              note = e.toString();
              debugPrint('PhilIriReading: $e');
            }
          }
          return _ReadingData(
            reading,
            passage,
            await vm.miscues(reading.id!),
            await vm.questions(passage.id!),
            await vm.answers(reading.id!),
            result,
            note,
          );
        },
        builder: (context, d, _) {
          if (d == null) return const EmptyNote('This reading is not on this device.');
          final r = d.reading;
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final byWord = {for (final m in d.miscues) m.wordIndex: m};
          final words = d.passage.words;
          return PageBody(
            children: [
              SectionCard(
                title: d.passage.title,
                children: [
                  InfoRow('Method', readingMethodLabel(r.method)),
                  InfoRow(
                    r.method == PhilIriReadingMethod.oneMinute ? 'Words read' : 'Time',
                    r.method == PhilIriReadingMethod.oneMinute
                        ? (r.wordsRead?.toString() ?? 'not yet')
                        : (r.readingSeconds == null ? 'not yet' : '${r.readingSeconds} s'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(onPressed: () => _timing(r), icon: const Icon(Icons.timer_outlined), label: const Text('Set timing')),
                  ),
                ],
              ),
              if (d.result != null)
                Card(
                  color: colors.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: colors.onPrimaryContainer),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Result: ${d.result!.profile.label}', style: theme.textTheme.titleMedium?.copyWith(color: colors.onPrimaryContainer)),
                        if (!d.result!.silent) Text('Word reading ${d.result!.wordReadingPercent}% (${d.result!.wordReadingLevel.label})'),
                        Text('${d.result!.wordsPerMinute.toStringAsFixed(0)} words per minute (${d.result!.speed.label})'),
                        Text(d.result!.comprehensionPercent == null
                            ? 'Comprehension: blank'
                            : 'Comprehension ${d.result!.comprehensionPercent}% (${d.result!.comprehensionLevel.label})'),
                        if (d.result!.isStrugglingReader) const Text('Struggling reader'),
                      ]),
                    ),
                  ),
                ),
              if (d.resultNote != null) Text('No result yet.', style: TextStyle(color: colors.onSurfaceVariant)),
              if (r.method.isOral)
                SectionCard(
                  title: 'Miscues (${d.miscues.where((m) => m.counts).length}) · tap a word',
                  children: [
                    if (d.passage.motivation != null)
                      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(d.passage.motivation!, style: theme.textTheme.bodySmall)),
                    Wrap(
                      spacing: 2,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < words.length; i++)
                          InkWell(
                            onTap: () => _word(i, words[i], byWord[i]),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              decoration: BoxDecoration(
                                color: byWord[i] == null
                                    ? null
                                    : byWord[i]!.selfCorrected
                                    ? colors.secondaryContainer
                                    : colors.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                words[i],
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: byWord[i] == null ? null : byWord[i]!.selfCorrected ? colors.onSecondaryContainer : colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final m in d.miscues)
                      Text('“${m.wordIndex < words.length ? words[m.wordIndex] : '?'}”: ${m.type.label}'
                          '${m.spokenText == null ? '' : ' (said “${m.spokenText}”)'}${m.selfCorrected ? ' · self-corrected' : ''}'),
                  ],
                ),
              SectionCard(
                title: 'Observations',
                children: [_Observations(value: r.observation, onChanged: _observe)],
              ),
              if (d.questions.isNotEmpty)
                SectionCard(
                  title: 'Comprehension',
                  children: [
                    for (final q in d.questions)
                      _QuestionTile(
                        question: q,
                        answer: d.answers.where((a) => a.questionId == q.id).firstOrNull,
                        onAnswer: (chosen, lb) => _answer(q, chosen, lb),
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

class _MiscueChoice {
  final bool remove;
  final PhilIriMiscueType? type;
  final String? spoken;
  final bool selfCorrected;
  const _MiscueChoice({this.remove = false, this.type, this.spoken, this.selfCorrected = false});
}

class _MiscueDialog extends StatefulWidget {
  final String word;
  final PhilIriMiscue? existing;
  const _MiscueDialog({required this.word, this.existing});

  @override
  State<_MiscueDialog> createState() => _MiscueDialogState();
}

class _MiscueDialogState extends State<_MiscueDialog> {
  late PhilIriMiscueType _type = widget.existing?.type ?? PhilIriMiscueType.mispronunciation;
  late bool _self = widget.existing?.selfCorrected ?? false;
  late final _spoken = TextEditingController(text: widget.existing?.spokenText ?? '');

  @override
  void dispose() {
    _spoken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('“${widget.word}”'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in PhilIriMiscueType.values)
                  ChoiceChip(label: Text(t.label), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _spoken, decoration: const InputDecoration(labelText: 'What the learner said (optional)')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _self,
                onChanged: (v) => setState(() => _self = v ?? false),
                title: const Text('Self-corrected (recorded, not counted)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(onPressed: () => Navigator.of(context).pop(const _MiscueChoice(remove: true)), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_MiscueChoice(
            type: _type,
            spoken: _spoken.text.trim().isEmpty ? null : _spoken.text.trim(),
            selfCorrected: _self,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Observations extends StatelessWidget {
  final PhilIriObservation value;
  final ValueChanged<PhilIriObservation> onChanged;
  const _Observations({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final o = value;
    PhilIriObservation copy({bool? a, bool? b, bool? c, bool? d, bool? e, bool? f}) => PhilIriObservation(
      wordByWord: a ?? o.wordByWord,
      lacksExpression: b ?? o.lacksExpression,
      voiceInaudible: c ?? o.voiceInaudible,
      disregardsPunctuation: d ?? o.disregardsPunctuation,
      pointsToWords: e ?? o.pointsToWords,
      littleAnalysis: f ?? o.littleAnalysis,
      other: o.other,
    );
    Widget box(String label, bool v, PhilIriObservation Function(bool) set) => CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: v,
      title: Text(label),
      onChanged: (x) => onChanged(set(x ?? false)),
    );
    return Column(children: [
      box('Does word-by-word reading', o.wordByWord, (x) => copy(a: x)),
      box('Lacks expression; monotonous tone', o.lacksExpression, (x) => copy(b: x)),
      box('Voice is hardly audible', o.voiceInaudible, (x) => copy(c: x)),
      box('Disregards punctuation', o.disregardsPunctuation, (x) => copy(d: x)),
      box('Points to each word with finger', o.pointsToWords, (x) => copy(e: x)),
      box('Employs little or no method of analysis', o.littleAnalysis, (x) => copy(f: x)),
    ]);
  }
}

class _QuestionTile extends StatelessWidget {
  final PhilIriQuestion question;
  final PhilIriAnswer? answer;
  final void Function(String? chosen, bool lookedBack) onAnswer;
  const _QuestionTile({required this.question, required this.answer, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final a = answer;
    final letters = [for (var i = 0; i < question.choices.length; i++) String.fromCharCode(97 + i)];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${question.questionNo}. ${question.prompt}${question.questionType == null ? '' : ' (${question.questionType!.code})'}'),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < letters.length; i++)
              ChoiceChip(
                label: Text('${letters[i]}. ${question.choices[i]}'),
                selected: a?.chosen == letters[i],
                onSelected: (_) => onAnswer(letters[i], a?.lookedBack ?? false),
              ),
            ChoiceChip(
              label: const Text("Doesn't know"),
              selected: a != null && a.chosen == null,
              onSelected: (_) => onAnswer(null, a?.lookedBack ?? false),
            ),
          ]),
          if (a != null)
            Row(children: [
              Text(a.isCorrect ? 'Correct' : 'Wrong', style: TextStyle(color: a.isCorrect ? colors.tertiary : colors.error)),
              const SizedBox(width: 12),
              FilterChip(label: const Text('Looked back'), selected: a.lookedBack, onSelected: (v) => onAnswer(a.chosen, v)),
            ]),
        ],
      ),
    );
  }
}
