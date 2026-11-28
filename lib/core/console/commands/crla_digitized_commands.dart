// lib/core/console/commands/crla_digitized_commands.dart

/// Digitized CRLA commands (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md):
/// one command per CrlaViewModel call, both builds. Item and word positions
/// are the form's (crla-form): items from 1, words from 0.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_viewmodel.dart';
import '../../models/crla_form.dart';
import '../../models/phil_iri_timer_event.dart' show isoWithOffset;

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

const _timeHelp = '[YYYY-MM-DDTHH:MM:SS[+HH:MM]]';

void registerCrlaDigitizedCommands(ConsoleRegistry registry, AuthViewModel authVm, CrlaViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        final guardError = authVm.requireActiveSession();
        if (guardError != null) return guardError;
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('crla-form', "crla-form <assessmentId> — the attempt's digitized form: Part 1 items, story text "
      '(sentences with word positions) and questions with accepted answers', (args) async {
    if (args.length != 1) throw const _Usage('Usage: crla-form <assessmentId>');
    final f = await vm.form(_int(args[0], 'assessmentId'));
    final lines = <String>[
      'Grade ${f.grade} ${f.language} (${f.variant}) · time limit ${_mmss(f.timeLimitSeconds)}',
      for (final e in f.items.entries)
        '${e.key.value}: ${[for (final i in e.value) '${i.itemNo} ${i.text}${i.answerKey == null ? '' : ' [${i.answerKey}]'}'].join(' | ')}',
    ];
    for (final s in f.stories) {
      lines.add('Story ${s.storyNo} · ${s.title} · ${s.wordCount} words');
      var first = 0;
      for (var n = 0; n < s.sentences.length; n++) {
        final words = s.sentences[n];
        lines.add('  ${n + 1}. [$first-${first + words.length - 1}] ${words.join(' ')}');
        first += words.length;
      }
      for (final q in s.questions) {
        lines.add('  Q${q.questionNo} (after sentence ${q.afterSentence}) ${q.question} — accepted: ${q.acceptedAnswers}');
      }
    }
    return lines.join('\n');
  });

  add('crla-digitized', "crla-digitized <assessmentId> — the attempt's marks and what they add up to", (args) async {
    if (args.length != 1) throw const _Usage('Usage: crla-digitized <assessmentId>');
    final s = await vm.digitized(_int(args[0], 'assessmentId'));
    return [
      _stateLine(s),
      for (final m in s.evidence.part1)
        '  ${m.task.value} ${m.itemNo}: ${m.selfCorrected ? 'self-corrected' : m.correct ? 'right' : 'wrong'}',
      for (final w in s.evidence.words) '  word ${w.wordIndex}: ${w.kind.value}',
      for (final a in s.evidence.answers) '  Q${a.questionNo}: ${a.mark.value}',
      for (final t in s.evidence.timer) '  ${t.seq}. ${t.kind.value} ${isoWithOffset(t.at)}',
    ].join('\n');
  });

  add('crla-mark', 'crla-mark <assessmentId> <task1|task2_low|task2_high|task2> <itemNo> <right|wrong|self> [confirm] '
      '— mark a Part 1 item (confirm: a Task 1 change that switches the Task 2 clears its marks)', (args) async {
    const usage = 'Usage: crla-mark <assessmentId> <task> <itemNo> <right|wrong|self> [confirm]';
    if (args.length < 4 || args.length > 5 || (args.length == 5 && args[4] != 'confirm')) throw const _Usage(usage);
    final mark = args[3];
    if (!const ['right', 'wrong', 'self'].contains(mark)) throw const _Usage(usage);
    final s = await vm.markItem(_int(args[0], 'assessmentId'), _task(args[1]), _int(args[2], 'itemNo'),
        correct: mark != 'wrong', selfCorrected: mark == 'self', confirm: args.length == 5);
    return _stateLine(s);
  });

  add('crla-unmark', 'crla-unmark <assessmentId> <task> <itemNo> [confirm] — remove an item\'s mark', (args) async {
    if (args.length < 3 || args.length > 4 || (args.length == 4 && args[3] != 'confirm')) {
      throw const _Usage('Usage: crla-unmark <assessmentId> <task> <itemNo> [confirm]');
    }
    return _stateLine(await vm.unmarkItem(_int(args[0], 'assessmentId'), _task(args[1]), _int(args[2], 'itemNo'),
        confirm: args.length == 4));
  });

  add('crla-task-done', 'crla-task-done <assessmentId> <task> — done with a task: the items not marked are wrong',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: crla-task-done <assessmentId> <task>');
    return _stateLine(await vm.closeTask(_int(args[0], 'assessmentId'), _task(args[1])));
  });

  add('crla-word', 'crla-word <assessmentId> <wordIndex> [self] — mark a story word a miscue (or self-corrected); '
      'the same mark again removes it', (args) async {
    if (args.length < 2 || args.length > 3 || (args.length == 3 && args[2] != 'self')) {
      throw const _Usage('Usage: crla-word <assessmentId> <wordIndex> [self]');
    }
    return _stateLine(await vm.toggleWord(_int(args[0], 'assessmentId'), _int(args[1], 'wordIndex'),
        kind: args.length == 3 ? CrlaWordMarkKind.selfCorrected : CrlaWordMarkKind.miscue));
  });

  add('crla-timer-start', 'crla-timer-start <assessmentId> <storyNo> $_timeHelp — start timing story 1 or 2',
      (args) async {
    if (args.length < 2 || args.length > 3) throw const _Usage('Usage: crla-timer-start <assessmentId> <storyNo> $_timeHelp');
    return _stateLine(await vm.startStoryTimer(_int(args[0], 'assessmentId'), _int(args[1], 'storyNo'),
        at: args.length == 3 ? _time(args[2]) : null));
  });

  for (final (name, help) in [
    ('crla-timer-pause', 'pause the timer (the learner stopped)'),
    ('crla-timer-resume', 'resume after a pause'),
    ('crla-timer-stop', 'stop the timer: the learner finished (after the limit it is dated at the limit)'),
    ('crla-timer-reset', 'restart after a mistake (the first timing stays in the record)'),
  ]) {
    add(name, '$name <assessmentId> $_timeHelp — $help', (args) async {
      if (args.isEmpty || args.length > 2) throw _Usage('Usage: $name <assessmentId> $_timeHelp');
      final id = _int(args[0], 'assessmentId');
      final at = args.length == 2 ? _time(args[1]) : null;
      final s = switch (name) {
        'crla-timer-pause' => await vm.pauseStoryTimer(id, at: at),
        'crla-timer-resume' => await vm.resumeStoryTimer(id, at: at),
        'crla-timer-stop' => await vm.stopStoryTimer(id, at: at),
        _ => await vm.resetStoryTimer(id, at: at),
      };
      return _stateLine(s);
    });
  }

  add('crla-timer', "crla-timer <assessmentId> — the story's timer now (stops itself at the grade's limit)",
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: crla-timer <assessmentId>');
    return _stateLine(await vm.storyTimer(_int(args[0], 'assessmentId')));
  });

  add('crla-last-word', 'crla-last-word <assessmentId> <wordIndex> — after the timer stopped: the last word '
      'the learner reached (0 = the first word)', (args) async {
    if (args.length != 2) throw const _Usage('Usage: crla-last-word <assessmentId> <wordIndex>');
    return _stateLine(await vm.setLastWordReached(_int(args[0], 'assessmentId'), _int(args[1], 'wordIndex')));
  });

  add('crla-answer', 'crla-answer <assessmentId> <questionNo> <right|wrong|na> — mark a comprehension question',
      (args) async {
    const usage = 'Usage: crla-answer <assessmentId> <questionNo> <right|wrong|na>';
    if (args.length != 3) throw const _Usage(usage);
    final mark = switch (args[2]) {
      'right' => CrlaAnswerMark.correct,
      'wrong' => CrlaAnswerMark.incorrect,
      'na' => CrlaAnswerMark.notAsked,
      _ => throw const _Usage(usage),
    };
    return _stateLine(await vm.answerQuestion(_int(args[0], 'assessmentId'), _int(args[1], 'questionNo'), mark));
  });

  add('crla-observe', 'crla-observe <assessmentId> [experience=<1-5>] [observation=<1-4>] [remarks=<text>] '
      "— Part 2's typed fields on a marked attempt (remarks takes the rest of the line)", (args) async {
    const usage = 'Usage: crla-observe <assessmentId> [experience=<1-5>] [observation=<1-4>] [remarks=<text>]';
    if (args.length < 2) throw const _Usage(usage);
    int? experience, observation;
    String? remarks;
    for (var i = 1; i < args.length; i++) {
      final a = args[i];
      if (a.startsWith('experience=')) {
        experience = _int(a.substring(11), 'experience');
      } else if (a.startsWith('observation=')) {
        observation = _int(a.substring(12), 'observation');
      } else if (a.startsWith('remarks=')) {
        remarks = [a.substring(8), ...args.sublist(i + 1)].join(' ');
        break;
      } else {
        throw const _Usage(usage);
      }
    }
    final p = await vm.saveObservation(_int(args[0], 'assessmentId'),
        learnerExperienceRating: experience, observationLevel: observation, remarks: remarks);
    return 'Part 2 of ${p.assessmentId}: experience ${p.learnerExperienceRating ?? '-'}, '
        'observation ${p.observationLevel ?? '-'}, remarks ${p.remarks ?? '-'}.';
  });
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

CrlaTask _task(String raw) {
  try {
    return CrlaTask.fromString(raw);
  } on ArgumentError {
    throw _Usage('Invalid task: "$raw" (task1, task2_low, task2_high or task2)');
  }
}

DateTime _time(String raw) =>
    strictTimeArg(raw) ?? (throw _Usage('"${raw.trim()}" is not a real time (YYYY-MM-DDTHH:MM:SS, optionally +08:00)'));

String _mmss(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _stateLine(CrlaDigitizedState s) {
  String task(CrlaTask t) => const {
        CrlaTask.task2Low: 'Task 2 (low)',
        CrlaTask.task2High: 'Task 2 (high)',
        CrlaTask.task2: 'Task 2',
      }[t]!;
  final parts = <String>[
    'Attempt ${s.assessmentId}',
    s.label,
    'Task 1 ${s.task1Score}${s.task1Done ? '' : ' (not done)'}',
    s.task2 == null ? 'no Task 2' : '${task(s.task2!)} ${s.task2Score ?? '-'}',
    if (s.storyNo != null) ...[
      'story ${s.storyNo} timer ${s.timerStatus.name} ${_mmss(s.timedSeconds ?? s.elapsed.inSeconds)} '
          '(limit ${_mmss(s.timeLimitSeconds)})',
      'miscues ${s.miscues}',
      'words read ${s.wordsRead ?? '-'}',
      'comprehension ${s.comprehension}',
      if (s.lastWordReached != null) 'last word ${s.lastWordReached}',
    ],
  ];
  return '${parts.join(' · ')}${s.lastWordNeeded ? '\nTap the last word the learner reached (crla-last-word).' : ''}';
}
