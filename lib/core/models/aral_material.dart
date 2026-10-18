// lib/core/models/aral_material.dart
//
// One ARAL learning material in the catalog (aral_materials): which program it
// is for (key stage + track; a null track on KS2/KS3 = either track), what it
// is (learner's material, tutor's guide, supplementary), its language and the
// learner grades it may go to. KS1-KS3 materials are for Grades 7-10 only
// (reading coordinator 2026-10-18); the cloud refuses KS3 below Grade 7.
// schoolId null = region-wide (superadmin); otherwise a school's own.
// No files are stored in BASA (owner 2026-10-18: any school must be able to run
// its own Supabase at little or no cost): fileName names the document the
// coordinator distributes (Google Drive or the installation package) and link
// points at it. A school can keep its own link (AralMaterialLink).
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
  final String? fileName;           // the document's file name, e.g. "RTP_AR_KS1_... .pdf"
  final String? link;               // http(s) URL, e.g. the Google Drive file
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
    this.link,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  String get programLabel => track == null
      ? (keyStage.hasTrack ? '${keyStage.label} (any track)' : keyStage.label)
      : '${keyStage.label} ${track!.label}';

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
        'link': link,
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
        link: m['link'] as String?,
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
    String? Function()? fileName,
    String? Function()? link,
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
        fileName: fileName != null ? fileName() : this.fileName,
        link: link != null ? link() : this.link,
        isActive: isActive ?? this.isActive,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A school's own link for a material (aral_material_links): coordinators
/// keep links working themselves, also for region-wide materials they can't edit.
class AralMaterialLink {
  final int? id;
  final int materialId;
  final int schoolId;
  final String link;
  final String? updatedBy;
  final String? updatedAt;

  AralMaterialLink({
    this.id,
    required this.materialId,
    required this.schoolId,
    required this.link,
    this.updatedBy,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'material_id': materialId,
        'school_id': schoolId,
        'link': link,
      };

  factory AralMaterialLink.fromMap(Map<String, Object?> m) => AralMaterialLink(
        id: m['id'] as int?,
        materialId: m['material_id'] as int,
        schoolId: m['school_id'] as int,
        link: m['link'] as String,
        updatedBy: m['updated_by'] as String?,
        updatedAt: m['updated_at'] as String?,
      );
}

/// An http(s) URL without spaces (the cloud CHECK).
bool aralMaterialLinkOk(String link) => RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(link);
