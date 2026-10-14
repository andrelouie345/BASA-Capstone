// lib/core/models/phil_iri_question.dart
import 'dart:convert';

/// Form 4 "Summary of Comprehension Responses" types. The English graded
/// passages don't label their questions, so a question's type may be null.
enum PhilIriQuestionType {
  literal('L'),
  inferential('I'),
  critical('C');

  final String code;
  const PhilIriQuestionType(this.code);

  static PhilIriQuestionType fromString(String value) {
    return PhilIriQuestionType.values.firstWhere(
      (t) => t.name == value || t.code == value,
      orElse: () => throw ArgumentError('Invalid PhilIriQuestionType value: $value'),
    );
  }
}

/// A multiple-choice comprehension question of a passage. Choices are in
/// letter order (a, b, c, ...); some questions have 3 choices, most have 4.
class PhilIriQuestion {
  final int? id;
  final int passageId;
  final int questionNo;               // 1-based, as printed
  final PhilIriQuestionType? questionType;
  final String prompt;
  final List<String> choices;
  final String answerKey;             // choice letter, e.g. 'b'

  PhilIriQuestion({
    this.id,
    required this.passageId,
    required this.questionNo,
    this.questionType,
    required this.prompt,
    required this.choices,
    required this.answerKey,
  });

  static String letterOf(int choiceIndex) =>
      String.fromCharCode('a'.codeUnitAt(0) + choiceIndex);

  /// True when [letter] is the key (case-insensitive).
  bool isCorrect(String letter) =>
      letter.trim().toLowerCase() == answerKey.toLowerCase();

  /// `choices` is a jsonb array in Postgres; the SQLite repo stores it as a
  /// JSON string (fromMap accepts both).
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'passage_id': passageId,
        'question_no': questionNo,
        'question_type': questionType?.code,
        'prompt': prompt,
        'choices': choices,
        'answer_key': answerKey.toLowerCase(),
      };

  factory PhilIriQuestion.fromMap(Map<String, Object?> m) {
    final raw = m['choices'];
    final list = raw is String ? jsonDecode(raw) as List : raw as List;
    final type = m['question_type'] as String?;
    return PhilIriQuestion(
      id: m['id'] as int?,
      passageId: m['passage_id'] as int,
      questionNo: m['question_no'] as int,
      questionType: type == null ? null : PhilIriQuestionType.fromString(type),
      prompt: m['prompt'] as String,
      choices: list.cast<String>(),
      answerKey: m['answer_key'] as String,
    );
  }
}
