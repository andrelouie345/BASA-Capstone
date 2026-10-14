// lib/core/models/phil_iri_rubric_score.dart
//
// A score on one rubric criterion of the collection used in a session, e.g.
// the FLT graphomotor section ("Spacing" = 3 on a 1–4 scale). Belongs to the
// session, not a passage reading: the graphomotor task is not a reading.

class PhilIriRubricScore {
  final int? id;
  final int assessmentId;
  final int criterionId;
  final int score;

  PhilIriRubricScore({
    this.id,
    required this.assessmentId,
    required this.criterionId,
    required this.score,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'assessment_id': assessmentId,
        'criterion_id': criterionId,
        'score': score,
      };

  factory PhilIriRubricScore.fromMap(Map<String, Object?> m) => PhilIriRubricScore(
        id: m['id'] as int?,
        assessmentId: m['assessment_id'] as int,
        criterionId: m['criterion_id'] as int,
        score: m['score'] as int,
      );
}
