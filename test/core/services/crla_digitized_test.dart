// Digitized CRLA rules (spec 2026-11-27 D1, D3, D4, D6, D7; plan Task 1).
import 'package:basa_capstone/core/models/crla_marks.dart';
import 'package:basa_capstone/core/services/crla_digitized.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sentences: one per line, words split on spaces, punctuation kept', () {
    expect(crlaStorySentences('Para flies away.\nIt is dark.'), [
      ['Para', 'flies', 'away.'],
      ['It', 'is', 'dark.'],
    ]);
    expect(crlaStoryWords('Para flies away.\nIt is dark.'), ['Para', 'flies', 'away.', 'It', 'is', 'dark.']);
  });

  test("Iba't and Puting-puti are one word each; blank lines and extra spaces ignored", () {
    expect(crlaStoryWords("Iba't ibang tao.\n\n  Puting-puti   ang ilong niya."), hasLength(7));
  });

  test('which Task 2 follows Task 1', () {
    expect(crlaTask2For('mt', 6), CrlaTask.task2Low);
    expect(crlaTask2For('fil', 7), CrlaTask.task2High);
    expect(crlaTask2For('eng', 0), isNull);
    expect(crlaTask2For('eng', 1), CrlaTask.task2);
  });

  CrlaPart1Mark item(CrlaTask t, int n, {bool correct = true, bool self = false}) =>
      CrlaPart1Mark(assessmentId: -1, task: t, itemNo: n, correct: correct, selfCorrected: self);

  test('task score counts right and self-corrected items of that task', () {
    final marks = [
      item(CrlaTask.task1, 1),
      item(CrlaTask.task1, 2, correct: false),
      item(CrlaTask.task1, 3, self: true),
      item(CrlaTask.task2Low, 1),
    ];
    expect(crlaTaskScore(marks, CrlaTask.task1), 2);
    expect(crlaTaskScore(marks, CrlaTask.task2Low), 1);
  });

  CrlaWordMark word(int i, [CrlaWordMarkKind k = CrlaWordMarkKind.miscue]) =>
      CrlaWordMark(assessmentId: -1, storyNo: 1, wordIndex: i, kind: k);

  test('words read: 100 words, no last word, 3 miscues -> 97; self-corrected words count as read', () {
    final marks = [word(1), word(5), word(9), word(12, CrlaWordMarkKind.selfCorrected)];
    expect(crlaDigitizedMiscues(marks, null), 3);
    expect(crlaDigitizedWordsRead(wordCount: 100, lastWordReached: null, marks: marks), 97);
  });

  test('last word 59, miscues at 10 and 70 -> 59', () {
    final marks = [word(10), word(70)];
    expect(crlaDigitizedMiscues(marks, 59), 1);
    expect(crlaDigitizedWordsRead(wordCount: 100, lastWordReached: 59, marks: marks), 59);
  });

  test("words reached are capped at the story's stored word count (a form whose text has more words)", () {
    // As the server: least(word_count, last + 1) - miscues.
    expect(crlaDigitizedWordsRead(wordCount: 50, lastWordReached: 50, marks: [word(3)]), 49);
  });

  test('comprehension counts correct only (not asked = 0)', () {
    CrlaAnswer a(int n, CrlaAnswerMark m) => CrlaAnswer(assessmentId: -1, storyNo: 1, questionNo: n, mark: m);
    expect(
        crlaComprehensionFromAnswers([
          a(1, CrlaAnswerMark.correct),
          a(2, CrlaAnswerMark.incorrect),
          a(3, CrlaAnswerMark.notAsked),
          a(4, CrlaAnswerMark.correct),
        ]),
        2);
  });

  test('marks round-trip through toMap/fromMap', () {
    final m = item(CrlaTask.task2High, 4, self: true);
    final back = CrlaPart1Mark.fromMap(m.toMap());
    expect((back.task, back.itemNo, back.correct, back.selfCorrected), (CrlaTask.task2High, 4, true, true));
    expect(m.toMap()['task'], 'task2_high');
    expect(CrlaWordMark.fromMap(word(3, CrlaWordMarkKind.selfCorrected).toMap()).kind, CrlaWordMarkKind.selfCorrected);
    final t = CrlaTimerEvent(
        assessmentId: -1, storyNo: 2, seq: 1, kind: CrlaTimerKind.start, at: DateTime.parse('2026-07-01T09:00:00+08:00'));
    final tb = CrlaTimerEvent.fromMap(t.toMap());
    expect(tb.at.isAtSameMomentAs(t.at), isTrue);
    expect(tb.storyNo, 2);
  });
}
