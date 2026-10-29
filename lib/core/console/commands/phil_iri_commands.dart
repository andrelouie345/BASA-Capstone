// lib/core/console/commands/phil_iri_commands.dart

/// Commands for Phil-IRI assessments (local, offline-first): GST, sessions,
/// the passage reading, miscues, comprehension answers, rubric scores, the
/// session lifecycle and results. Content comes from the local mirror
/// (phil-iri-content commands or pull-cloud).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/phil_iri_viewmodel.dart';
import '../../models/phil_iri_assessment.dart';
import '../../models/phil_iri_miscue.dart';
import '../../models/phil_iri_passage.dart';
import '../../models/phil_iri_reading.dart';
import '../../models/phil_iri_types.dart';
import 'phil_iri_command_helpers.dart';

void registerPhilIriCommands(ConsoleRegistry registry, PhilIriViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on PhilIriUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  // ---- GST ----

  add(
      'phil-iri-gst',
      'phil-iri-gst <studentId> <sectionId> <schoolYear> <total> [literal inferential critical] '
          '— record a Group Screening Test (out of 20 for Grades 4-6, 40 for 7-10; a retake is another call)',
      (args) async {
    const usage = 'Usage: phil-iri-gst <studentId> <sectionId> <schoolYear> <total> [literal inferential critical]';
    if (args.length != 4 && args.length != 7) throw const PhilIriUsage(usage);
    final g = await vm.recordGst(
      studentId: philIriInt(args[0], 'studentId'),
      sectionId: philIriInt(args[1], 'sectionId'),
      schoolYear: args[2],
      totalScore: philIriInt(args[3], 'total'),
      literalCorrect: args.length == 7 ? philIriInt(args[4], 'literal') : null,
      inferentialCorrect: args.length == 7 ? philIriInt(args[5], 'inferential') : null,
      criticalCorrect: args.length == 7 ? philIriInt(args[6], 'critical') : null,
    );
    final passed = await vm.gstPassed(g);
    return 'Recorded GST ${g.id} (attempt ${g.attemptNo}): ${g.totalScore}/${g.maxScore} '
        '(${g.wholePercent}%, ${passed ? 'passed' : 'below the cut-off'}).';
  });

  add('phil-iri-gst-list', 'phil-iri-gst-list <sectionId> [schoolYear] — GST results of a section', (args) async {
    if (args.isEmpty || args.length > 2) throw const PhilIriUsage('Usage: phil-iri-gst-list <sectionId> [schoolYear]');
    final list = await vm.gstForSection(philIriInt(args[0], 'sectionId'), schoolYear: args.length > 1 ? args[1] : null);
    if (list.isEmpty) return 'No GST results.';
    return list.map((g) {
      final parts = g.literalCorrect == null ? '' : ' (L ${g.literalCorrect}, I ${g.inferentialCorrect}, C ${g.criticalCorrect})';
      return '[${g.id}] student ${g.studentId} · ${g.schoolYear} · attempt ${g.attemptNo} · '
          '${g.totalScore}/${g.maxScore}$parts · ${g.takenAt}';
    }).join('\n');
  });

  // ---- Sessions ----

  add(
      'phil-iri-start',
      'phil-iri-start <studentId> <sectionId> <schoolYear> <bosy|mosy1|mosy2|mosy3|eosy> '
          '— start a session in a Grade 4-10 section (a retake is another start)', (args) async {
    if (args.length != 4) {
      throw const PhilIriUsage('Usage: phil-iri-start <studentId> <sectionId> <schoolYear> <bosy|mosy1|mosy2|mosy3|eosy>');
    }
    final s = await vm.startSession(
      studentId: philIriInt(args[0], 'studentId'),
      sectionId: philIriInt(args[1], 'sectionId'),
      schoolYear: args[2],
      round: philIriRound(args[3]),
    );
    return 'Started session ${s.id}: ${_sessionLine(s)}';
  });

  add('phil-iri-sessions', 'phil-iri-sessions <sectionId> [schoolYear] [round] — the sessions of a section',
      (args) async {
    if (args.isEmpty || args.length > 3) throw const PhilIriUsage('Usage: phil-iri-sessions <sectionId> [schoolYear] [round]');
    await vm.loadForSection(philIriInt(args[0], 'sectionId'),
        schoolYear: args.length > 1 ? args[1] : null, round: args.length > 2 ? philIriRound(args[2]) : null);
    if (vm.assessments.isEmpty) return 'No sessions.';
    return vm.assessments.map((s) => '[${s.id}] ${_sessionLine(s)}').join('\n');
  });

  add('phil-iri-session', 'phil-iri-session <assessmentId> — a session: its reading, miscues, answers, rubric and score',
      (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-session <assessmentId>');
    final s = await vm.getSession(philIriInt(args[0], 'assessmentId'));
    if (s == null) return 'No session with id ${args[0]}.';
    final out = StringBuffer('[${s.id}] ${_sessionLine(s)}');
    final readings = await vm.readings(s.id!);
    if (readings.isEmpty) {
      out.write('\nNo reading yet (phil-iri-passages-for ${s.id}, then phil-iri-read).');
      return out.toString();
    }
    for (final r in readings) {
      final p = await vm.passage(r.passageId);
      out.write('\nReading ${r.id}: passage ${r.passageId}'
          '${p == null ? ' (not on this device)' : ' "${p.title}" (${p.level == null ? 'no level' : 'Grade ${p.level}'}, ${p.wordCount} words)'}'
          ' · ${_timing(r)}');
      final obs = _observationText(r.observation);
      if (obs.isNotEmpty) out.write('\n  Observed: $obs');
      final words = p?.words ?? const <String>[];

      final miscues = await vm.miscues(r.id!);
      final counted = miscues.where((m) => m.counts).length;
      out.write('\n  Miscues: $counted counted, ${miscues.length - counted} self-corrected');
      for (final m in miscues) {
        out.write('\n    [${m.id}] ${_miscueText(m, words)}');
      }

      if (p != null) {
        final questions = await vm.questions(p.id!);
        if (questions.isNotEmpty) {
          final answers = {for (final a in await vm.answers(r.id!)) a.questionId: a};
          final right = answers.values.where((a) => a.isCorrect).length;
          out.write('\n  Answers: $right of ${questions.length} correct');
          final silent = answers.isEmpty ? await vm.silentReadingFollowedUp(r.id!) : null;
          if (silent != null) {
            out.write(' · not asked again: the score uses the answers of silent reading ${silent.id} '
                '(session ${silent.assessmentId})');
          }
          for (final q in questions) {
            final a = answers[q.id];
            final text = a == null
                ? 'not answered'
                : '${a.chosen ?? 'x (does not know)'} · ${a.isCorrect ? 'correct' : 'wrong'}${a.lookedBack ? ' · looked back' : ''}';
            out.write('\n    Q${q.questionNo} [${q.id}] $text');
          }
        }
        final collection = await vm.collection(p.collectionId);
        final criteria = await vm.rubricCriteria(p.collectionId);
        if (criteria.isNotEmpty) {
          final scores = {for (final x in await vm.rubricScores(s.id!)) x.criterionId: x.score};
          out.write('\n  Rubric (${collection?.name ?? 'collection ${p.collectionId}'}):');
          for (final k in criteria) {
            out.write('\n    [${k.id}] ${k.name}: ${scores[k.id] ?? '-'} (${k.scaleMin}..${k.scaleMax})');
          }
        }
      }

      if (r.isTimed) {
        out.write('\n  ${s.isFinalized ? 'Frozen result' : 'Score now'}: ${_resultText(await vm.scoreReading(r.id!))}');
      }
    }
    return out.toString();
  });

  add(
      'phil-iri-passages-for',
      'phil-iri-passages-for <assessmentId> [whole|minute|silent] — the passages this session may use '
          '(oral by default: a text read silently in this round is listed first, for the oral follow-up)', (args) async {
    if (args.isEmpty || args.length > 2) {
      throw const PhilIriUsage('Usage: phil-iri-passages-for <assessmentId> [whole|minute|silent]');
    }
    final list = await vm.availablePassages(philIriInt(args[0], 'assessmentId'),
        method: args.length == 2 ? _method(args[1]) : PhilIriReadingMethod.wholeText);
    if (list.isEmpty) return 'No usable passages on this device (pull-cloud, or add content).';
    return list.map(_passageLine).join('\n');
  });

  // ---- Reading ----

  add(
      'phil-iri-read',
      'phil-iri-read <assessmentId> <passageId> [whole [seconds] | minute [wordsRead] | silent [seconds]] '
          '— start the session\'s passage reading (whole text aloud by default; time can come later; '
          'silent = read silently, timed, no miscues)', (args) async {
    const usage =
        'Usage: phil-iri-read <assessmentId> <passageId> [whole [seconds] | minute [wordsRead] | silent [seconds]]';
    if (args.length < 2 || args.length > 4) throw const PhilIriUsage(usage);
    final method = args.length < 3 ? PhilIriReadingMethod.wholeText : _method(args[2]);
    final oneMinute = method == PhilIriReadingMethod.oneMinute;
    final n = args.length == 4 ? philIriInt(args[3], oneMinute ? 'wordsRead' : 'seconds') : null;
    final r = await vm.startReading(
      assessmentId: philIriInt(args[0], 'assessmentId'),
      passageId: philIriInt(args[1], 'passageId'),
      method: method,
      readingSeconds: oneMinute ? null : n,
      wordsRead: oneMinute ? n : null,
    );
    return 'Started reading ${r.id} of passage ${r.passageId} · ${_timing(r)}.';
  });

  add('phil-iri-time',
      'phil-iri-time <readingId> <seconds|words> <n> — the reading time (whole text, silent) or words read in the minute',
      (args) async {
    if (args.length != 3) throw const PhilIriUsage('Usage: phil-iri-time <readingId> <seconds|words> <n>');
    final n = philIriInt(args[2], args[1]);
    final r = switch (args[1]) {
      'seconds' => await vm.saveTiming(philIriInt(args[0], 'readingId'), readingSeconds: n),
      'words' => await vm.saveTiming(philIriInt(args[0], 'readingId'), wordsRead: n),
      _ => throw const PhilIriUsage('Usage: phil-iri-time <readingId> <seconds|words> <n>'),
    };
    return 'Reading ${r.id}: ${_timing(r)}.';
  });

  add(
      'phil-iri-observe',
      'phil-iri-observe <readingId> [wordbyword] [noexpression] [inaudible] [punctuation] [pointing] [noanalysis] '
          '[other "<text>"] — replace the oral reading observation checklist (no flags clears it)', (args) async {
    if (args.isEmpty) throw const PhilIriUsage('Usage: phil-iri-observe <readingId> [flags...] [other "<text>"]');
    final flags = <String>{};
    String? other;
    for (var i = 1; i < args.length; i++) {
      if (args[i] == 'other') {
        if (i + 1 >= args.length) throw const PhilIriUsage('other needs a text: other "<text>"');
        other = args.sublist(i + 1).join(' ');
        break;
      }
      if (!_observationFlags.contains(args[i])) {
        throw PhilIriUsage('Unknown observation "${args[i]}". Use: ${_observationFlags.join(', ')}, other "<text>".');
      }
      flags.add(args[i]);
    }
    final r = await vm.saveObservation(
        philIriInt(args[0], 'readingId'),
        PhilIriObservation(
          wordByWord: flags.contains('wordbyword'),
          lacksExpression: flags.contains('noexpression'),
          voiceInaudible: flags.contains('inaudible'),
          disregardsPunctuation: flags.contains('punctuation'),
          pointsToWords: flags.contains('pointing'),
          littleAnalysis: flags.contains('noanalysis'),
          other: other,
        ));
    final text = _observationText(r.observation);
    return 'Reading ${r.id} observation: ${text.isEmpty ? 'nothing noted' : text}.';
  });

  add('phil-iri-reading-delete',
      'phil-iri-reading-delete <readingId> — remove the reading with its miscues and answers (to use another passage)',
      (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-reading-delete <readingId>');
    final id = philIriInt(args[0], 'readingId');
    await vm.deleteReading(id);
    return 'Deleted reading $id.';
  });

  // ---- Miscues ----

  add(
      'phil-iri-miscue',
      'phil-iri-miscue <readingId> <wordIndex> <type> [sc] [spoken text...] — mark a miscue on a word '
          '(positions from phil-iri-passage-show; an insertion goes BEFORE the word; sc = self-corrected, not counted)',
      (args) async {
    if (args.length < 3) throw const PhilIriUsage('Usage: phil-iri-miscue <readingId> <wordIndex> <type> [sc] [spoken text...]');
    final sc = args.length > 3 && args[3] == 'sc';
    final spoken = args.sublist(sc ? 4 : 3).join(' ');
    final m = await vm.markMiscue(
      readingId: philIriInt(args[0], 'readingId'),
      wordIndex: philIriInt(args[1], 'wordIndex'),
      type: _miscueType(args[2]),
      selfCorrected: sc,
      spokenText: spoken.isEmpty ? null : spoken,
    );
    return 'Marked miscue ${m.id}: ${_miscueText(m, const [])}.';
  });

  add(
      'phil-iri-miscue-update',
      'phil-iri-miscue-update <readingId> <miscueId> <wordIndex> <type> [sc] [spoken text...] — replace a miscue',
      (args) async {
    if (args.length < 4) {
      throw const PhilIriUsage('Usage: phil-iri-miscue-update <readingId> <miscueId> <wordIndex> <type> [sc] [spoken text...]');
    }
    final sc = args.length > 4 && args[4] == 'sc';
    final spoken = args.sublist(sc ? 5 : 4).join(' ');
    final m = await vm.updateMiscue(PhilIriMiscue(
      readingId: philIriInt(args[0], 'readingId'),
      id: philIriInt(args[1], 'miscueId'),
      wordIndex: philIriInt(args[2], 'wordIndex'),
      type: _miscueType(args[3]),
      selfCorrected: sc,
      spokenText: spoken.isEmpty ? null : spoken,
    ));
    return 'Updated miscue ${m.id}: ${_miscueText(m, const [])}.';
  });

  add('phil-iri-miscue-remove', 'phil-iri-miscue-remove <miscueId> — remove a miscue', (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-miscue-remove <miscueId>');
    final id = philIriInt(args[0], 'miscueId');
    await vm.removeMiscue(id);
    return 'Removed miscue $id.';
  });

  // ---- Comprehension and rubric ----

  add(
      'phil-iri-answer',
      'phil-iri-answer <readingId> <questionId> <letter|x> [lb] — record an answer '
          '(x = does not know, counted wrong; lb = looked back at the passage; again replaces it)', (args) async {
    if (args.length < 3 || args.length > 4 || (args.length == 4 && args[3] != 'lb')) {
      throw const PhilIriUsage('Usage: phil-iri-answer <readingId> <questionId> <letter|x> [lb]');
    }
    final a = await vm.answer(
      readingId: philIriInt(args[0], 'readingId'),
      questionId: philIriInt(args[1], 'questionId'),
      chosen: args[2].toLowerCase() == 'x' ? null : args[2],
      lookedBack: args.length == 4,
    );
    return 'Answer to question ${a.questionId}: ${a.chosen ?? 'x'} · ${a.isCorrect ? 'correct' : 'wrong'}'
        '${a.lookedBack ? ' · looked back' : ''}.';
  });

  add('phil-iri-rubric', 'phil-iri-rubric <assessmentId> <criterionId> <score> — score one rubric criterion (again replaces it)',
      (args) async {
    if (args.length != 3) throw const PhilIriUsage('Usage: phil-iri-rubric <assessmentId> <criterionId> <score>');
    final x = await vm.scoreRubric(
      assessmentId: philIriInt(args[0], 'assessmentId'),
      criterionId: philIriInt(args[1], 'criterionId'),
      score: philIriInt(args[2], 'score'),
    );
    return 'Session ${x.assessmentId}: criterion ${x.criterionId} scored ${x.score}.';
  });

  // ---- Lifecycle ----

  add('phil-iri-complete', 'phil-iri-complete <assessmentId> — mark a session done (needs the timed reading)',
      (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-complete <assessmentId>');
    final s = await vm.complete(philIriInt(args[0], 'assessmentId'));
    return 'Session ${s.id} is ${s.status.value}.';
  });

  add('phil-iri-reopen', 'phil-iri-reopen <assessmentId> — put a completed session back in progress', (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-reopen <assessmentId>');
    final s = await vm.reopen(philIriInt(args[0], 'assessmentId'));
    return 'Session ${s.id} is ${s.status.value}.';
  });

  add('phil-iri-discard', 'phil-iri-discard <assessmentId> — throw away an in-progress session and everything in it',
      (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-discard <assessmentId>');
    final id = philIriInt(args[0], 'assessmentId');
    await vm.discard(id);
    return 'Discarded session $id.';
  });

  // ---- Results ----

  add('phil-iri-score', 'phil-iri-score <readingId> — one reading scored (frozen once finalized)', (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-score <readingId>');
    return _resultText(await vm.scoreReading(philIriInt(args[0], 'readingId')));
  });

  add(
      'phil-iri-results',
      'phil-iri-results <studentId> <sectionId> <schoolYear> [current] — a learner\'s year: every round and the end '
          'result (current = regenerate with today\'s thresholds; nothing stored changes)', (args) async {
    if (args.length < 3 || args.length > 4 || (args.length == 4 && args[3] != 'current')) {
      throw const PhilIriUsage('Usage: phil-iri-results <studentId> <sectionId> <schoolYear> [current]');
    }
    final r = await vm.learnerResults(
      studentId: philIriInt(args[0], 'studentId'),
      sectionId: philIriInt(args[1], 'sectionId'),
      schoolYear: args[2],
      useCurrentThresholds: args.length == 4,
    );
    final out = StringBuffer('Student ${r.studentId} · Grade ${r.learnerGrade} · ${r.schoolYear}'
        '${r.regenerated ? ' · regenerated with today\'s thresholds' : ''}');
    final g = r.gst;
    out.write('\nGST: ${g == null ? 'none' : '${g.totalScore}/${g.maxScore} (${g.wholePercent}%, attempt ${g.attemptNo})'}');
    for (final round in r.rounds) {
      final s = r.sessions[round.round];
      final status = s == null ? 'not given' : 'session ${s.id} ${s.status.value}';
      final carried = !round.given && round.profile != null; // an earlier round's result
      out.write('\n${round.round.label.padRight(8)} ${carried ? '(carried) ' : ''}$status · ${_roundText(round)}');
      final a = round.actual;
      if (a != null) {
        // The true current score, for the tutor (the line above is what reports use).
        final level = round.actualAdjustedLevel == null
            ? ''
            : ' · adjusted ${round.actualAdjustedLevelLabel} · ${round.actualLevelsDownLabel}';
        out.write('\n${''.padRight(9)}true score: ${_resultText(a)}$level');
      }
    }
    out.write('\nEnd result: ${r.end == null ? 'none yet' : '${r.end!.round.label} · ${_roundText(r.end!)}'}');
    return out.toString();
  });
}

PhilIriReadingMethod _method(String raw) => switch (raw) {
      'whole' => PhilIriReadingMethod.wholeText,
      'minute' => PhilIriReadingMethod.oneMinute,
      'silent' => PhilIriReadingMethod.silent,
      _ => throw PhilIriUsage('Reading method is whole, minute or silent (got "$raw")'),
    };

/// A miscue type by name, label or unique prefix ("omi", "sub").
PhilIriMiscueType _miscueType(String raw) {
  final key = raw.toLowerCase();
  final matches = PhilIriMiscueType.values.where((t) => t.name.startsWith(key)).toList();
  if (key.isNotEmpty && matches.length == 1) return matches.single;
  throw PhilIriUsage('Miscue type is one of ${PhilIriMiscueType.values.map((t) => t.name).join(', ')} '
      '(a unique start is enough; got "$raw")');
}

const _observationFlags = ['wordbyword', 'noexpression', 'inaudible', 'punctuation', 'pointing', 'noanalysis'];

String _observationText(PhilIriObservation o) => o.labels.join(', ');

String _timing(PhilIriReading r) => switch (r.method) {
      PhilIriReadingMethod.wholeText =>
        'whole text, ${r.readingSeconds == null ? 'not timed yet' : '${r.readingSeconds} s'}',
      PhilIriReadingMethod.silent =>
        'silent, whole text, ${r.readingSeconds == null ? 'not timed yet' : '${r.readingSeconds} s'} (no miscues)',
      PhilIriReadingMethod.oneMinute =>
        'one minute, ${r.wordsRead == null ? 'words read not recorded yet' : '${r.wordsRead} words read'}',
    };

String _miscueText(PhilIriMiscue m, List<String> words) {
  final where = m.type == PhilIriMiscueType.insertion
      ? (m.wordIndex >= words.length && words.isNotEmpty ? 'after the last word' : 'before word ${m.wordIndex}')
      : 'word ${m.wordIndex}';
  final word = m.wordIndex < words.length ? ' "${words[m.wordIndex]}"' : '';
  return '$where$word · ${m.type.label}'
      '${m.spokenText == null ? '' : ' "${m.spokenText}"'}${m.selfCorrected ? ' · self-corrected (not counted)' : ''}';
}

String _pct(int? percent) => percent == null ? 'blank' : '$percent%';

String _resultText(PhilIriPassageResult r) =>
    '${r.silent ? 'silent · ' : ''}word reading ${_pct(r.wordReadingPercent)} (${r.accuracyLevel.label}), '
    '${r.wordsPerMinute.round()} wpm '
    '(${r.speed.label}) -> ${r.wordReadingLevel.label}; comprehension ${_pct(r.comprehensionPercent)} '
    '(${r.comprehensionLevel.label}); profile ${r.profile.label}';

String _roundText(PhilIriRoundResult r) {
  if (r.profile == null) return 'no result yet';
  final level = r.adjustedLevel == null ? '' : ' · adjusted ${r.adjustedLevelLabel} · ${r.levelsDownLabel}';
  return 'WR ${_pct(r.wordReadingPercent)} ${r.wordReadingLevel?.label ?? '-'}, '
      '${r.wordsPerMinute?.round() ?? '-'} wpm ${r.speed?.label ?? '-'}, '
      'comp ${_pct(r.comprehensionPercent)} ${r.comprehensionLevel?.label ?? '-'} -> ${r.profile!.label}$level';
}

String _sessionLine(PhilIriAssessment s) =>
    'student ${s.studentId} · section ${s.sectionId} · ${s.schoolYear} · ${s.round.label} attempt ${s.attemptNo} · '
    '${s.status.value} · ${s.assessedAt}';

String _passageLine(PhilIriPassage p) => [
      '[${p.id}] ${p.title}',
      'collection ${p.collectionId}',
      if (p.level != null) 'Grade ${p.level}',
      if (p.setCode != null) 'set ${p.setCode}',
      '${p.wordCount} words',
    ].join(' · ');

