// lib/core/services/crla_digitized.dart
//
// Digitized CRLA rules (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md):
// a story's words, which Task 2 Task 1 leads to, and the totals the marks
// give. The same rules are in the SQLite triggers (crla_local_schema.dart) and
// on the server (20261127010000_crla_digitized.sql): change them together.
import '../models/crla_marks.dart';

/// A story's sentences (one per line of its text) and their words: split on
/// spaces, punctuation kept with its word, as DepEd counts them ("Iba't" and
/// "Puting-puti" are one word each). Blank lines are skipped.
List<List<String>> crlaStorySentences(String body) => [
      for (final line in body.split('\n'))
        if (line.trim().isNotEmpty) line.trim().split(RegExp(r'\s+')),
    ];

/// A story's words in reading order (word marks point at these, 0-based).
List<String> crlaStoryWords(String body) => [for (final s in crlaStorySentences(body)) ...s];

/// The Task 2 a Task 1 score leads to: standard forms (mt/fil) the low Task 2
/// below 7, else the high one; English Task 2 from 1 up, none at 0 (the test
/// ends). Same rule as the Part 1 CHECKs.
CrlaTask? crlaTask2For(String variant, int task1Score) {
  if (variant == 'eng') return task1Score == 0 ? null : CrlaTask.task2;
  return task1Score < 7 ? CrlaTask.task2Low : CrlaTask.task2High;
}

/// A task's score: its items marked right or self-corrected.
int crlaTaskScore(List<CrlaPart1Mark> marks, CrlaTask task) =>
    marks.where((m) => m.task == task && m.counts).length;

/// The miscues that count: miscue marks up to [lastWordReached] (all when null).
int crlaDigitizedMiscues(List<CrlaWordMark> marks, int? lastWordReached) => marks
    .where((m) => m.kind == CrlaWordMarkKind.miscue && (lastWordReached == null || m.wordIndex <= lastWordReached))
    .length;

/// Words read of a marked story: the words up to the last word reached (the
/// whole story when null) minus the miscues among them (spec D6). The words
/// reached never pass the story's stored [wordCount] (a form whose text has
/// more words than it prints), as the server's least(word_count, last + 1).
int crlaDigitizedWordsRead({required int wordCount, int? lastWordReached, required List<CrlaWordMark> marks}) {
  final reached = lastWordReached == null || lastWordReached + 1 > wordCount ? wordCount : lastWordReached + 1;
  return reached - crlaDigitizedMiscues(marks, lastWordReached);
}

/// Comprehension correct: the questions marked correct (not asked counts as
/// not correct, spec D7).
int crlaComprehensionFromAnswers(List<CrlaAnswer> answers) =>
    answers.where((a) => a.mark == CrlaAnswerMark.correct).length;
