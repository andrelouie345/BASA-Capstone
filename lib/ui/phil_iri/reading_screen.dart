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
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete reading'))),
            ],
          ),
        ],
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
          if (d == null) return const EmptyNote('This reading is not on this device.', icon: Icons.cloud_off_outlined);
          final r = d.reading;
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final byWord = {for (final m in d.miscues) m.wordIndex: m};
          final words = d.passage.words;
          final oneMinute = r.method == PhilIriReadingMethod.oneMinute;
          final summary = SectionCard(
            title: d.passage.title,
            icon: Icons.menu_book_outlined,
            trailing: FilledButton.tonalIcon(onPressed: () => _timing(r), icon: const Icon(Icons.timer_outlined), label: const Text('Set timing')),
            children: [
              StatGrid(tileWidth: 170, tiles: [
                StatTile(label: 'Method', value: readingMethodLabel(r.method), icon: Icons.record_voice_over_outlined),
                StatTile(
                  label: oneMinute ? 'Words read' : 'Time',
                  value: oneMinute
                      ? (r.wordsRead?.toString() ?? 'not yet')
                      : (r.readingSeconds == null ? 'not yet' : '${r.readingSeconds} s'),
                  icon: Icons.timer_outlined,
                ),
                if (r.method.isOral)
                  StatTile(label: 'Miscues', value: '${d.miscues.where((m) => m.counts).length}', icon: Icons.spellcheck),
              ]),
            ],
          );
          final res = d.result;
          final result = res == null
              ? null
              : Card(
                  color: colors.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: colors.onPrimaryContainer),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          IconBadge(Icons.insights, size: 36, background: colors.primary, foreground: colors.onPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Result: ${res.profile.label}',
                                style: theme.textTheme.titleMedium?.copyWith(color: colors.onPrimaryContainer)),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        if (!res.silent) Text('Word reading ${res.wordReadingPercent}% (${res.wordReadingLevel.label})'),
                        Text('${res.wordsPerMinute.toStringAsFixed(0)} words per minute (${res.speed.label})'),
                        Text(res.comprehensionPercent == null
                            ? 'Comprehension: blank'
                            : 'Comprehension ${res.comprehensionPercent}% (${res.comprehensionLevel.label})'),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          StatusChip(res.profile.label, tone: philIriLevelTone(res.profile)),
                        ]),
                      ]),
                    ),
                  ),
                );
          final miscues = !r.method.isOral
              ? null
              : SectionCard(
                  title: 'Miscues (${d.miscues.where((m) => m.counts).length}) · tap a word',
                  icon: Icons.spellcheck,
                  children: [
                    if (d.passage.motivation != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(d.passage.motivation!,
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ),
                    const _Legend(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < words.length; i++)
                          _WordTarget(word: words[i], miscue: byWord[i], onTap: () => _word(i, words[i], byWord[i])),
                      ],
                    ),
                    if (d.miscues.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      for (final m in d.miscues)
                        ListRow(
                          leading: IconBadge(
                            m.selfCorrected ? Icons.undo : Icons.close,
                            size: 32,
                            background: m.selfCorrected ? colors.tertiaryContainer : colors.errorContainer,
                            foreground: m.selfCorrected ? colors.onTertiaryContainer : colors.onErrorContainer,
                          ),
                          title: '“${m.wordIndex < words.length ? words[m.wordIndex] : '?'}”: ${m.type.label}'
                              '${m.spokenText == null ? '' : ' (said “${m.spokenText}”)'}${m.selfCorrected ? ' · self-corrected' : ''}',
                          onTap: m.wordIndex < words.length ? () => _word(m.wordIndex, words[m.wordIndex], m) : null,
                        ),
                    ],
                  ],
                );
          final observations = SectionCard(
            title: 'Observations',
            icon: Icons.visibility_outlined,
            children: [_Observations(value: r.observation, onChanged: _observe)],
          );
          final comprehension = d.questions.isEmpty
              ? null
              : SectionCard(
                  title: 'Comprehension',
                  icon: Icons.quiz_outlined,
                  children: [
                    for (var i = 0; i < d.questions.length; i++) ...[
                      if (i > 0) const Divider(),
                      _QuestionTile(
                        question: d.questions[i],
                        answer: d.answers.where((a) => a.questionId == d.questions[i].id).firstOrNull,
                        onAnswer: (chosen, lb) => _answer(d.questions[i], chosen, lb),
                      ),
                    ],
                  ],
                );
          final noResult = d.resultNote == null
              ? null
              : const NoticeBanner('No result yet.', icon: Icons.hourglass_empty, tone: StatusTone.neutral);
          return LayoutBuilder(builder: (context, c) {
            // Wide: the passage and its miscues left, observations and answers right.
            if (c.maxWidth >= 1000) {
              Widget column(List<Widget?> items) {
                final list = items.whereType<Widget>().toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < list.length; i++) ...[if (i > 0) const SizedBox(height: 16), list[i]],
                ]);
              }

              return PageBody(
                maxWidth: 1280,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: column([summary, result, noResult, miscues])),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: column([observations, comprehension])),
                  ]),
                ],
              );
            }
            return PageBody(children: [summary, ?result, ?noResult, ?miscues, observations, ?comprehension]);
          });
        },
      ),
    );
  }
}

/// One passage word, a comfortable tap target, tinted when it has a miscue.
class _WordTarget extends StatelessWidget {
  final String word;
  final PhilIriMiscue? miscue;
  final VoidCallback onTap;
  const _WordTarget({required this.word, required this.miscue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final m = miscue;
    final (bg, fg, border) = m == null
        ? (colors.surfaceContainerLowest, colors.onSurface, colors.outlineVariant)
        : m.selfCorrected
        ? (colors.tertiaryContainer, colors.onTertiaryContainer, colors.tertiary)
        : (colors.errorContainer, colors.onErrorContainer, colors.error);
    final target = Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                word,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: fg,
                  fontWeight: m == null ? null : FontWeight.w600,
                  decoration: m != null && !m.selfCorrected ? TextDecoration.lineThrough : null,
                  decorationColor: fg,
                ),
              ),
            ),
          ),
        ),
      );
    return m == null ? target : Tooltip(message: m.type.label, child: target);
  }
}

/// What the word colours mean.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget item(String label, Color bg, Color border) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: border)),
      ),
      const SizedBox(width: 6),
      Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
    ]);
    return Wrap(spacing: 16, runSpacing: 8, children: [
      item('Not marked', colors.surfaceContainerLowest, colors.outlineVariant),
      item('Miscue (counted)', colors.errorContainer, colors.error),
      item('Self-corrected', colors.tertiaryContainer, colors.tertiary),
    ]);
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
    final theme = Theme.of(context);
    final a = answer;
    final letters = [for (var i = 0; i < question.choices.length; i++) String.fromCharCode(97 + i)];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LetterBadge('${question.questionNo}', size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${question.questionNo}. ${question.prompt}${question.questionType == null ? '' : ' (${question.questionType!.code})'}',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ]),
          const SizedBox(height: 8),
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
          if (a != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(
                a.isCorrect ? 'Correct' : 'Wrong',
                tone: a.isCorrect ? StatusTone.good : StatusTone.bad,
                icon: a.isCorrect ? Icons.check : Icons.close,
              ),
              FilterChip(label: const Text('Looked back'), selected: a.lookedBack, onSelected: (v) => onAnswer(a.chosen, v)),
            ]),
          ],
        ],
      ),
    );
  }
}
