// lib/core/models/phil_iri_passage.dart
//
// A reading passage of a material collection (see phil_iri_collection.dart).
// Passages are data, not code: coordinators add passages to their school's
// collections or deactivate ones they don't use. Content approval happens
// outside BASA.

final _whitespace = RegExp(r'\s+');

class PhilIriPassage {
  final int? id;
  final int collectionId;
  final String language;        // 'English' (only language in scope)
  final String? testType;       // 'pre' | 'post' for Phil-IRI sets; null otherwise
  final String? setCode;        // 'A'..'D' for Phil-IRI sets; null otherwise
  final int? level;             // passage grade level 1–10; null in non-graded collections (FRB)
  final int? selectionNo;       // number in the collection's reading order (FRB); null otherwise
  final String title;
  final String? motivation;     // motivation / motive question read before the passage
  final String body;            // passage text; paragraphs separated by '\n'
  final int wordCount;          // the source's "No. of words"
  final int learnerGradeMin;    // learner grades this passage is meant for
  final int learnerGradeMax;    //   (2018 sets: 4–6, JHS 2024 sets: 7–10)
  final bool isActive;
  final String? createdBy;      // users.id

  PhilIriPassage({
    this.id,
    required this.collectionId,
    this.language = 'English',
    this.testType,
    this.setCode,
    this.level,
    this.selectionNo,
    required this.title,
    this.motivation,
    required this.body,
    required this.wordCount,
    required this.learnerGradeMin,
    required this.learnerGradeMax,
    this.isActive = true,
    this.createdBy,
  });

  /// The words the tutor taps, in reading order. A miscue's wordIndex is a
  /// position in this list. Splits on whitespace only, so "Mr." and "lily-pad"
  /// are one word each and punctuation stays attached.
  List<String> get words =>
      body.trim().isEmpty ? const [] : body.trim().split(_whitespace);

  /// True when the tokenized words agree with the declared word count.
  /// A mismatch means the text or the count was entered wrong.
  bool get wordCountMatches => words.length == wordCount;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'collection_id': collectionId,
        'language': language,
        'test_type': testType,
        'set_code': setCode,
        'level': level,
        'selection_no': selectionNo,
        'title': title,
        'motivation': motivation,
        'body': body,
        'word_count': wordCount,
        'learner_grade_min': learnerGradeMin,
        'learner_grade_max': learnerGradeMax,
        'is_active': isActive,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory PhilIriPassage.fromMap(Map<String, Object?> m) => PhilIriPassage(
        id: m['id'] as int?,
        collectionId: m['collection_id'] as int,
        language: m['language'] as String,
        testType: m['test_type'] as String?,
        setCode: m['set_code'] as String?,
        level: m['level'] as int?,
        selectionNo: m['selection_no'] as int?,
        title: m['title'] as String,
        motivation: m['motivation'] as String?,
        body: m['body'] as String,
        wordCount: m['word_count'] as int,
        learnerGradeMin: m['learner_grade_min'] as int,
        learnerGradeMax: m['learner_grade_max'] as int,
        isActive: m['is_active'] is bool
            ? m['is_active'] as bool
            : (m['is_active'] as int? ?? 1) == 1,
        createdBy: m['created_by'] as String?,
      );
}
