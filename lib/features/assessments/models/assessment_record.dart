class AssessmentRecord {
  final String id;
  final String learnerName;
  final String learnerId;
  final String assessmentType; // 'GST', 'CRLA', 'Phil-IRI'
  final String date;
  final String score;
  final String percentage; // e.g. "85%", "—"
  final String readingLevel; // e.g. "At-Level", "Flagged", "Frustration", "Instructional", "Independent"
  final String status; // e.g. "Completed", "Pending", "Flagged", "At-Level"
  final String remarks;

  const AssessmentRecord({
    required this.id,
    required this.learnerName,
    required this.learnerId,
    required this.assessmentType,
    required this.date,
    required this.score,
    required this.percentage,
    required this.readingLevel,
    required this.status,
    required this.remarks,
  });
}
