// lib/core/models/crla_marks.dart
//
// Digitized CRLA (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md):
// the content a form adds (Part 1 items, story questions) and the evidence an
// attempt keeps (item marks, word marks, answers, timer taps). Evidence rows
// are synced children of crla_assessments.
import '../services/reading_timer.dart';
import 'phil_iri_timer_event.dart' show isoWithOffset;

export '../services/reading_timer.dart' show TimerTapKind, TimerStatus;

/// The CRLA timer's tap kinds are the shared reading timer's.
typedef CrlaTimerKind = TimerTapKind;

/// A Part 1 task of a form: standard forms (mt/fil) have Task 1 and a low or
/// high Task 2; English has Task 1 and Task 2.
enum CrlaTask {
  task1('task1'),
  task2Low('task2_low'),
  task2High('task2_high'),
  task2('task2');

  final String value;
  const CrlaTask(this.value);

  static CrlaTask fromString(String s) =>
      values.firstWhere((t) => t.value == s, orElse: () => throw ArgumentError('CRLA task "$s"'));
}

/// A Part 2 word mark: a miscue (counted) or self-corrected (recorded, not
/// counted). An unmarked word was read correctly.
enum CrlaWordMarkKind {
  miscue('miscue'),
  selfCorrected('self_corrected');

  final String value;
  const CrlaWordMarkKind(this.value);

  static CrlaWordMarkKind fromString(String s) =>
      values.firstWhere((k) => k.value == s, orElse: () => throw ArgumentError('CRLA word mark "$s"'));
}

/// A comprehension question's mark, as DepEd's form: ✓, ✗ or N/A.
enum CrlaAnswerMark {
  correct('correct'),
  incorrect('incorrect'),
  notAsked('not_asked');

  final String value;
  const CrlaAnswerMark(this.value);

  static CrlaAnswerMark fromString(String s) =>
      values.firstWhere((k) => k.value == s, orElse: () => throw ArgumentError('CRLA answer mark "$s"'));
}

bool _bool(Object? v) => v is bool ? v : (v as num? ?? 0) == 1;

/// One marked Part 1 item. A self-corrected item counts as right.
class CrlaPart1Mark {
  final int? id;
  final int assessmentId;
  final CrlaTask task;
  final int itemNo;
  final bool correct;
  final bool selfCorrected;
  final String? createdBy;

  const CrlaPart1Mark({
    this.id,
    required this.assessmentId,
    required this.task,
    required this.itemNo,
    required this.correct,
    this.selfCorrected = false,
    this.createdBy,
  });

  /// Right, or self-corrected (DepEd: a self-correction gets the point).
  bool get counts => correct || selfCorrected;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'task': task.value,
        'item_no': itemNo,
        'correct': correct,
        'self_corrected': selfCorrected,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory CrlaPart1Mark.fromMap(Map<String, Object?> m) => CrlaPart1Mark(
        id: (m['id'] as num?)?.toInt(),
        assessmentId: (m['assessment_id'] as num).toInt(),
        task: CrlaTask.fromString(m['task'] as String),
        itemNo: (m['item_no'] as num).toInt(),
        correct: _bool(m['correct']),
        selfCorrected: _bool(m['self_corrected']),
        createdBy: m['created_by'] as String?,
      );
}

/// One marked Part 2 word ([wordIndex] 0-based in the story).
class CrlaWordMark {
  final int? id;
  final int assessmentId;
  final int storyNo;
  final int wordIndex;
  final CrlaWordMarkKind kind;
  final String? createdBy;

  const CrlaWordMark({
    this.id,
    required this.assessmentId,
    required this.storyNo,
    required this.wordIndex,
    required this.kind,
    this.createdBy,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'story_no': storyNo,
        'word_index': wordIndex,
        'kind': kind.value,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory CrlaWordMark.fromMap(Map<String, Object?> m) => CrlaWordMark(
        id: (m['id'] as num?)?.toInt(),
        assessmentId: (m['assessment_id'] as num).toInt(),
        storyNo: (m['story_no'] as num).toInt(),
        wordIndex: (m['word_index'] as num).toInt(),
        kind: CrlaWordMarkKind.fromString(m['kind'] as String),
        createdBy: m['created_by'] as String?,
      );
}

/// One comprehension question's mark.
class CrlaAnswer {
  final int? id;
  final int assessmentId;
  final int storyNo;
  final int questionNo;
  final CrlaAnswerMark mark;
  final String? createdBy;

  const CrlaAnswer({
    this.id,
    required this.assessmentId,
    required this.storyNo,
    required this.questionNo,
    required this.mark,
    this.createdBy,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'story_no': storyNo,
        'question_no': questionNo,
        'mark': mark.value,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory CrlaAnswer.fromMap(Map<String, Object?> m) => CrlaAnswer(
        id: (m['id'] as num?)?.toInt(),
        assessmentId: (m['assessment_id'] as num).toInt(),
        storyNo: (m['story_no'] as num).toInt(),
        questionNo: (m['question_no'] as num).toInt(),
        mark: CrlaAnswerMark.fromString(m['mark'] as String),
        createdBy: m['created_by'] as String?,
      );
}

/// One tap of an attempt's Part 2 timing log (insert-only once on the server).
class CrlaTimerEvent {
  final int? id;
  final int assessmentId;
  final int storyNo;
  final int seq;
  final CrlaTimerKind kind;
  final DateTime at;
  final String? createdBy;
  final String? createdAt;

  const CrlaTimerEvent({
    this.id,
    required this.assessmentId,
    required this.storyNo,
    required this.seq,
    required this.kind,
    required this.at,
    this.createdBy,
    this.createdAt,
  });

  TimerTap get tap => (kind: kind, at: at);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'story_no': storyNo,
        'seq': seq,
        'kind': kind.value,
        'at': isoWithOffset(at),
        if (createdBy != null) 'created_by': createdBy,
      };

  factory CrlaTimerEvent.fromMap(Map<String, Object?> m) => CrlaTimerEvent(
        id: (m['id'] as num?)?.toInt(),
        assessmentId: (m['assessment_id'] as num).toInt(),
        storyNo: (m['story_no'] as num).toInt(),
        seq: (m['seq'] as num).toInt(),
        kind: TimerTapKind.fromString(m['kind'] as String),
        at: DateTime.parse(m['at'] as String),
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

/// All of an attempt's evidence.
class CrlaEvidence {
  final List<CrlaPart1Mark> part1;
  final List<CrlaWordMark> words;
  final List<CrlaAnswer> answers;
  final List<CrlaTimerEvent> timer;
  const CrlaEvidence({this.part1 = const [], this.words = const [], this.answers = const [], this.timer = const []});

  bool get isEmpty => part1.isEmpty && words.isEmpty && answers.isEmpty && timer.isEmpty;
}

/// One Part 1 item of a form (content; one point each). [sentenceNo] groups
/// the words of a sentence task; null for a list of letters or words.
class CrlaPart1Item {
  final int? id;
  final int regionId;
  final String language;
  final int grade;
  final CrlaTask task;
  final int itemNo;
  final String text;
  final int? sentenceNo;
  /// The printed correct response of an item checked against a key (Grade 1
  /// rhyming word pairs: "Rhyme" / "No"); null for items read aloud.
  final String? answerKey;

  const CrlaPart1Item({
    this.id,
    required this.regionId,
    required this.language,
    required this.grade,
    required this.task,
    required this.itemNo,
    required this.text,
    this.sentenceNo,
    this.answerKey,
  });

  factory CrlaPart1Item.fromMap(Map<String, Object?> m) => CrlaPart1Item(
        id: (m['id'] as num?)?.toInt(),
        regionId: (m['region_id'] as num).toInt(),
        language: m['language'] as String,
        grade: (m['grade'] as num).toInt(),
        task: CrlaTask.fromString(m['task'] as String),
        itemNo: (m['item_no'] as num).toInt(),
        text: m['text'] as String,
        sentenceNo: (m['sentence_no'] as num?)?.toInt(),
        answerKey: m['answer_key'] as String?,
      );
}

/// One comprehension question of a story (content), with the accepted
/// answers as DepEd prints them; asked after sentence [afterSentence] (1-based).
class CrlaStoryQuestion {
  final int? id;
  final int storyId;
  final int questionNo;
  final int afterSentence;
  final String question;
  final String acceptedAnswers;

  const CrlaStoryQuestion({
    this.id,
    required this.storyId,
    required this.questionNo,
    required this.afterSentence,
    required this.question,
    required this.acceptedAnswers,
  });

  factory CrlaStoryQuestion.fromMap(Map<String, Object?> m) => CrlaStoryQuestion(
        id: (m['id'] as num?)?.toInt(),
        storyId: (m['story_id'] as num).toInt(),
        questionNo: (m['question_no'] as num).toInt(),
        afterSentence: (m['after_sentence'] as num).toInt(),
        question: m['question'] as String,
        acceptedAnswers: m['accepted_answers'] as String,
      );
}
