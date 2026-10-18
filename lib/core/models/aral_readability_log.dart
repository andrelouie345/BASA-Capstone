// lib/core/models/aral_readability_log.dart
//
// One reading selection used in a learner's ARAL intervention
// (aral_readability_logs): date, title, counts (words, sentences, syllables)
// and source. The readability scores are computed from the counts when read
// (aral_readability.dart), not stored. Kept only while the school's
// foundational literacy program (SHARP) is on. Offline-first like the
// check-ins: origin 'local' = written on this device, not uploaded yet.

class AralReadabilityLog {
  final int? id;
  final int enrollmentId;
  final String readOn;          // YYYY-MM-DD
  final String title;
  final int words;
  final int sentences;
  final int syllables;
  final String? source;         // URL / bibliographic entry / reference
  final int? materialId;        // the catalog material, when it is one
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;
  final String origin;          // local-only column: 'local' | 'cloud'

  AralReadabilityLog({
    this.id,
    required this.enrollmentId,
    required this.readOn,
    required this.title,
    required this.words,
    required this.sentences,
    required this.syllables,
    this.source,
    this.materialId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.origin = 'local',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'enrollment_id': enrollmentId,
        'read_on': readOn,
        'title': title,
        'words': words,
        'sentences': sentences,
        'syllables': syllables,
        'source': source,
        'material_id': materialId,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory AralReadabilityLog.fromMap(Map<String, Object?> m) => AralReadabilityLog(
        id: m['id'] as int?,
        enrollmentId: m['enrollment_id'] as int,
        readOn: (m['read_on'] as String).substring(0, 10),
        title: m['title'] as String,
        words: m['words'] as int,
        sentences: m['sentences'] as int,
        syllables: m['syllables'] as int,
        source: m['source'] as String?,
        materialId: m['material_id'] as int?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        origin: m['origin'] as String? ?? 'cloud',
      );

  AralReadabilityLog copyWith({
    String? readOn,
    String? title,
    int? words,
    int? sentences,
    int? syllables,
    String? Function()? source,
    int? Function()? materialId,
  }) =>
      AralReadabilityLog(
        id: id,
        enrollmentId: enrollmentId,
        readOn: readOn ?? this.readOn,
        title: title ?? this.title,
        words: words ?? this.words,
        sentences: sentences ?? this.sentences,
        syllables: syllables ?? this.syllables,
        source: source != null ? source() : this.source,
        materialId: materialId != null ? materialId() : this.materialId,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
        origin: origin,
      );
}
