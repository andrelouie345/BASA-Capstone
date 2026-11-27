// lib/core/repositories/crla_digitized_repository.dart
//
// Digitized CRLA (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md):
// a form's content and an attempt's evidence on the device. The ViewModel
// works on the device's copy only (synced like every assessment), so there is
// no server implementation.
import '../models/crla_marks.dart';

abstract class CrlaDigitizedRepository {
  /// The Part 1 items of a form, by task and item number.
  Future<List<CrlaPart1Item>> part1Items({required int regionId, required String language, required int grade});

  /// The story's text (one sentence per line), or null when it has none.
  Future<String?> storyBody(int storyId);

  /// The story's comprehension questions, by number.
  Future<List<CrlaStoryQuestion>> questions(int storyId);

  /// Marks an item (adds the row, or changes the item's existing mark).
  Future<void> setPart1Mark(CrlaPart1Mark mark);
  Future<void> deletePart1Mark(int assessmentId, CrlaTask task, int itemNo);

  /// Every mark of [task] (a Task 2 that no longer applies).
  Future<void> deletePart1Marks(int assessmentId, CrlaTask task);

  /// Marks a word (adds the row, or changes the word's existing kind).
  Future<void> setWordMark(CrlaWordMark mark);
  Future<void> deleteWordMark(int assessmentId, int wordIndex);

  /// Marks a question (adds the row, or changes its existing mark).
  Future<void> setAnswer(CrlaAnswer answer);

  Future<CrlaTimerEvent> insertTimerEvent(CrlaTimerEvent event);

  /// All of an attempt's evidence (marks by task and item, words by index,
  /// answers by number, timer taps by seq).
  Future<CrlaEvidence> evidence(int assessmentId);

  Future<bool> hasEvidence(int assessmentId);

  /// Removes the Part 1 row of an attempt made on this device and not sent
  /// (its last Part 1 mark was removed; final review C1).
  Future<void> deletePart1(int assessmentId);

  /// Attempts with timer taps not on the server yet, with the learner's name
  /// (the check before sending, final review I2).
  Future<List<({int assessmentId, String lastName, String firstName})>> attemptsWithUnsentTimerTaps();
}
