// lib/core/models/crla_form.dart
//
// What a digitized CRLA screen shows (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md):
// the attempt's form (CrlaViewModel.form) and its marking state
// (CrlaViewModel.digitized).
import 'crla_marks.dart';

export 'crla_marks.dart';

/// One story of a form, split as it is marked: sentences (one per line of the
/// record form) and the words in reading order (word marks point at these).
class CrlaFormStory {
  final int storyNo;
  final String title;

  /// The story's stored word count, which Part 2 is scored with. A few DepEd
  /// forms print a total that differs from their text; this is the printed one.
  final int wordCount;
  final List<List<String>> sentences;
  final List<String> words;
  final List<CrlaStoryQuestion> questions;

  const CrlaFormStory({
    required this.storyNo,
    required this.title,
    required this.wordCount,
    required this.sentences,
    required this.words,
    required this.questions,
  });
}

/// An attempt's digitized form: Part 1 items per task (in item order) and the
/// stories it can be read from (story 1 first).
class CrlaForm {
  final int assessmentId;
  final String variant;
  final String language;
  final int grade;
  final Map<CrlaTask, List<CrlaPart1Item>> items;
  final List<CrlaFormStory> stories;

  /// The grade's reading-time limit; the timer stops itself there.
  final int timeLimitSeconds;

  const CrlaForm({
    required this.assessmentId,
    required this.variant,
    required this.language,
    required this.grade,
    required this.items,
    required this.stories,
    required this.timeLimitSeconds,
  });
}

/// An attempt's marks and what they add up to.
class CrlaDigitizedState {
  final int assessmentId;
  final CrlaEvidence evidence;

  /// Marked in BASA (any mark or timer tap); false = totals typed in.
  final bool isDigitized;

  final int task1Score;

  /// Task 1 has every item marked.
  final bool task1Done;

  /// The Task 2 the Task 1 score leads to; null when the test ends (English
  /// Task 1 = 0).
  final CrlaTask? task2;

  /// Null while that Task 2 has no marks.
  final int? task2Score;

  /// The story being read (from its marks and timer); null before the timer starts.
  final int? storyNo;
  final TimerStatus timerStatus;

  /// Reading time so far (pauses left out), up to the stop when stopped.
  final Duration elapsed;

  /// The seconds of a stopped timing; null otherwise.
  final int? timedSeconds;
  final int timeLimitSeconds;

  /// The timer stopped at the limit: the tutor taps the last word reached.
  final bool lastWordNeeded;
  final int? lastWordReached;
  final int miscues;

  /// Null until the story's Part 2 is saved (stopped, last word given).
  final int? wordsRead;
  final int comprehension;

  const CrlaDigitizedState({
    required this.assessmentId,
    required this.evidence,
    required this.isDigitized,
    required this.task1Score,
    required this.task1Done,
    required this.task2,
    required this.task2Score,
    required this.storyNo,
    required this.timerStatus,
    required this.elapsed,
    required this.timedSeconds,
    required this.timeLimitSeconds,
    required this.lastWordNeeded,
    required this.lastWordReached,
    required this.miscues,
    required this.wordsRead,
    required this.comprehension,
  });

  String get label => isDigitized ? 'Marked in BASA' : 'Totals typed in';
}
