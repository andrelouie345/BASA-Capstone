// lib/core/models/aral_material.dart
//
// One ARAL learning material in the catalog (aral_materials): which program it
// is for (key stage + track; a null track on KS2/KS3 = either track), what it
// is (learner's material, tutor's guide, supplementary), its language and the
// learner grades it may go to. KS1-KS3 materials are for Grades 7-10 only
// (reading coordinator 2026-10-18); the cloud refuses KS3 below Grade 7.
// schoolId null = region-wide (superadmin); otherwise a school's own.
// The file fields are filled by the storage piece (R3b).
import 'aral_enrollment.dart' show AralKeyStage, AralTrack;

enum AralMaterialKind {
  learner('Learner\'s material'),
  tutor('Tutor\'s guide'),
  supplementary('Supplementary');

  final String label;
  const AralMaterialKind(this.label);

  static AralMaterialKind fromString(String v) => AralMaterialKind.values.firstWhere(
        (k) => k.name == v || k.label == v,
        orElse: () => throw ArgumentError('Invalid AralMaterialKind value: $v'),
      );
}

/// Languages a material can be in (ARAL Basic has a Filipino strand).
const aralMaterialLanguages = ['English', 'Filipino'];

/// Default learner grades: the ARAL materials are for high school.
const aralMaterialDefaultMinGrade = 7;
const aralMaterialDefaultMaxGrade = 10;

class AralMaterial {
  final int? id;
  final int? schoolId;              // null = region-wide
  final String title;
  final String? description;
  final AralKeyStage keyStage;
  final AralTrack? track;           // KS2/KS3: null = either track; Foundational/KS1: always null
  final AralMaterialKind kind;
  final String language;
  final int minGrade;
  final int maxGrade;
  final String? fileName;
  final int? fileSize;              // bytes
  final String? fileSha256;
  final String? storagePath;        // object path in the materials bucket (R3b)
  final bool isActive;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  AralMaterial({
    this.id,
    this.schoolId,
    required this.title,
    this.description,
    required this.keyStage,
    this.track,
    this.kind = AralMaterialKind.learner,
    this.language = 'English',
    this.minGrade = aralMaterialDefaultMinGrade,
    this.maxGrade = aralMaterialDefaultMaxGrade,
    this.fileName,
    this.fileSize,
    this.fileSha256,
    this.storagePath,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  String get programLabel => track == null
      ? (keyStage.hasTrack ? '${keyStage.label} (any track)' : keyStage.label)
      : '${keyStage.label} ${track!.label}';

  bool get hasFile => storagePath != null;

  /// Is this material for a learner in [keyStage]/[track] and [grade]?
  bool fits(AralKeyStage keyStage, AralTrack? track, int grade) =>
      isActive &&
      this.keyStage == keyStage &&
      (this.track == null || this.track == track) &&
      grade >= minGrade &&
      grade <= maxGrade;

  /// Stamps (created_by/at, updated_at) are set by the database, never sent.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'title': title,
        'description': description,
        'key_stage': keyStage.name,
        'track': track?.name,
        'kind': kind.name,
        'language': language,
        'min_grade': minGrade,
        'max_grade': maxGrade,
        'file_name': fileName,
        'file_size': fileSize,
        'file_sha256': fileSha256,
        'storage_path': storagePath,
        'is_active': isActive,
      };

  factory AralMaterial.fromMap(Map<String, Object?> m) => AralMaterial(
        id: m['id'] as int?,
        schoolId: m['school_id'] as int?,
        title: m['title'] as String,
        description: m['description'] as String?,
        keyStage: AralKeyStage.fromString(m['key_stage'] as String),
        track: m['track'] == null ? null : AralTrack.fromString(m['track'] as String),
        kind: AralMaterialKind.fromString(m['kind'] as String),
        language: m['language'] as String,
        minGrade: m['min_grade'] as int,
        maxGrade: m['max_grade'] as int,
        fileName: m['file_name'] as String?,
        fileSize: (m['file_size'] as num?)?.toInt(),
        fileSha256: m['file_sha256'] as String?,
        storagePath: m['storage_path'] as String?,
        isActive: m['is_active'] is bool ? m['is_active'] as bool : (m['is_active'] as int? ?? 1) == 1,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  AralMaterial copyWith({
    String? title,
    String? Function()? description,
    AralKeyStage? keyStage,
    AralTrack? Function()? track,
    AralMaterialKind? kind,
    String? language,
    int? minGrade,
    int? maxGrade,
    bool? isActive,
  }) =>
      AralMaterial(
        id: id,
        schoolId: schoolId,
        title: title ?? this.title,
        description: description != null ? description() : this.description,
        keyStage: keyStage ?? this.keyStage,
        track: track != null ? track() : this.track,
        kind: kind ?? this.kind,
        language: language ?? this.language,
        minGrade: minGrade ?? this.minGrade,
        maxGrade: maxGrade ?? this.maxGrade,
        fileName: fileName,
        fileSize: fileSize,
        fileSha256: fileSha256,
        storagePath: storagePath,
        isActive: isActive ?? this.isActive,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
