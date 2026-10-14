// lib/core/models/phil_iri_answer.dart
//
// A learner's answer to one comprehension question of a reading.
// isCorrect is stored at answer time (not looked up later), so editing a
// question's key afterwards never changes a recorded result.

class PhilIriAnswer {
  final int? id;
  final int readingId;
  final int questionId;
  final String? chosen;         // choice letter; null = "I don't know" (marked X)
  final bool isCorrect;
  final bool lookedBack;        // "LB": learner went back to the passage (still counts)

  PhilIriAnswer({
    this.id,
    required this.readingId,
    required this.questionId,
    this.chosen,
    required this.isCorrect,
    this.lookedBack = false,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'reading_id': readingId,
        'question_id': questionId,
        'chosen': chosen?.toLowerCase(),
        'is_correct': isCorrect,
        'looked_back': lookedBack,
      };

  factory PhilIriAnswer.fromMap(Map<String, Object?> m) => PhilIriAnswer(
        id: m['id'] as int?,
        readingId: m['reading_id'] as int,
        questionId: m['question_id'] as int,
        chosen: m['chosen'] as String?,
        isCorrect: _bool(m['is_correct']),
        lookedBack: _bool(m['looked_back']),
      );
}

bool _bool(Object? v) => v is bool ? v : (v as int? ?? 0) == 1;
