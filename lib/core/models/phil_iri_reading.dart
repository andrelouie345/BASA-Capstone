// lib/core/models/phil_iri_reading.dart
//
// One passage read within an assessment session (Form 3 per passage).
// Raw inputs: the passage, timing, miscues (PhilIriMiscue) and comprehension
// answers (PhilIriAnswer). The result fields below stay null while the session
// is open (results are computed live) and are written once when the session is
// finalized, so a finalized result never changes.
import '../services/phil_iri_rules.dart';

enum PhilIriReadingMethod {
  wholeText('whole_text'),   // timed reading of the whole passage
  oneMinute('one_minute');   // words read in one minute (wpm = words read)

  final String value;
  const PhilIriReadingMethod(this.value);

  static PhilIriReadingMethod fromString(String value) {
    return PhilIriReadingMethod.values.firstWhere(
      (m) => m.value == value || m.name == value,
      orElse: () => throw ArgumentError('Invalid PhilIriReadingMethod value: $value'),
    );
  }
}

/// Form 4 Oral Reading Observation Checklist (true = behaviour observed).
class PhilIriObservation {
  final bool wordByWord;          // Does word-by-word reading
  final bool lacksExpression;     // Lacks expression; monotonous tone
  final bool voiceInaudible;      // Voice is hardly audible
  final bool disregardsPunctuation;
  final bool pointsToWords;       // Points to each word with finger
  final bool littleAnalysis;      // Employs little or no method of analysis
  final String? other;            // Other observations

  const PhilIriObservation({
    this.wordByWord = false,
    this.lacksExpression = false,
    this.voiceInaudible = false,
    this.disregardsPunctuation = false,
    this.pointsToWords = false,
    this.littleAnalysis = false,
    this.other,
  });
}

class PhilIriReading {
  final int? id;
  final int assessmentId;
  final int sequenceNo;           // order read within the session, 1-based
  final int passageId;
  final PhilIriReadingMethod method;
  final int? readingSeconds;      // whole-text: time taken; null until timed
  final int? wordsRead;           // one-minute: words read in the minute
  final PhilIriObservation observation;

  /// The result columns: written only by the repository's finalize().
  static const resultColumns = [
    'word_reading_score', 'words_per_minute', 'accuracy_level', 'speed',
    'word_reading_level', 'comprehension_score', 'comprehension_level', 'profile',
  ];

  // Results, written only at finalization (null while live).
  final double? wordReadingScore;     // 0–1
  final double? wordsPerMinute;
  final PhilIriLevel? accuracyLevel;
  final PhilIriSpeed? speed;
  final PhilIriLevel? wordReadingLevel;
  final double? comprehensionScore;   // 0–1; null when the collection has none
  final PhilIriLevel? comprehensionLevel;
  final PhilIriLevel? profile;

  PhilIriReading({
    this.id,
    required this.assessmentId,
    required this.sequenceNo,
    required this.passageId,
    this.method = PhilIriReadingMethod.wholeText,
    this.readingSeconds,
    this.wordsRead,
    this.observation = const PhilIriObservation(),
    this.wordReadingScore,
    this.wordsPerMinute,
    this.accuracyLevel,
    this.speed,
    this.wordReadingLevel,
    this.comprehensionScore,
    this.comprehensionLevel,
    this.profile,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'sequence_no': sequenceNo,
        'passage_id': passageId,
        'method': method.value,
        'reading_seconds': readingSeconds,
        'words_read': wordsRead,
        'obs_word_by_word': observation.wordByWord,
        'obs_lacks_expression': observation.lacksExpression,
        'obs_voice_inaudible': observation.voiceInaudible,
        'obs_disregards_punctuation': observation.disregardsPunctuation,
        'obs_points_to_words': observation.pointsToWords,
        'obs_little_analysis': observation.littleAnalysis,
        'obs_other': observation.other,
        'word_reading_score': wordReadingScore,
        'words_per_minute': wordsPerMinute,
        'accuracy_level': accuracyLevel?.name,
        'speed': speed?.name,
        'word_reading_level': wordReadingLevel?.name,
        'comprehension_score': comprehensionScore,
        'comprehension_level': comprehensionLevel?.name,
        'profile': profile?.name,
      };

  factory PhilIriReading.fromMap(Map<String, Object?> m) => PhilIriReading(
        id: m['id'] as int?,
        assessmentId: m['assessment_id'] as int,
        sequenceNo: m['sequence_no'] as int,
        passageId: m['passage_id'] as int,
        method: PhilIriReadingMethod.fromString(m['method'] as String),
        readingSeconds: m['reading_seconds'] as int?,
        wordsRead: m['words_read'] as int?,
        observation: PhilIriObservation(
          wordByWord: _bool(m['obs_word_by_word']),
          lacksExpression: _bool(m['obs_lacks_expression']),
          voiceInaudible: _bool(m['obs_voice_inaudible']),
          disregardsPunctuation: _bool(m['obs_disregards_punctuation']),
          pointsToWords: _bool(m['obs_points_to_words']),
          littleAnalysis: _bool(m['obs_little_analysis']),
          other: m['obs_other'] as String?,
        ),
        wordReadingScore: (m['word_reading_score'] as num?)?.toDouble(),
        wordsPerMinute: (m['words_per_minute'] as num?)?.toDouble(),
        accuracyLevel: _level(m['accuracy_level']),
        speed: m['speed'] == null ? null : PhilIriSpeed.fromString(m['speed'] as String),
        wordReadingLevel: _level(m['word_reading_level']),
        comprehensionScore: (m['comprehension_score'] as num?)?.toDouble(),
        comprehensionLevel: _level(m['comprehension_level']),
        profile: _level(m['profile']),
      );
}

bool _bool(Object? v) => v is bool ? v : (v as int? ?? 0) == 1;

PhilIriLevel? _level(Object? v) => v == null ? null : PhilIriLevel.fromString(v as String);
