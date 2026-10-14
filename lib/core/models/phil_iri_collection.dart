// lib/core/models/phil_iri_collection.dart
//
// A material collection groups passages and says how they are used.
// - Prescribed collections (Phil-IRI 2018, Phil-IRI JHS 2024) are region-wide
//   (schoolId null), managed by the superadmin, and the only ones counted in
//   DepEd submission reports.
// - School-owned collections (e.g. Foundational Literacy Test, First Readers
//   Booklets) are visible to that school only and switched on/off by its
//   admin/coordinator. The superadmin can promote one to region-wide.
// Every reading records its passage, and through it its collection, so reports
// can filter "prescribed only".
import 'dart:convert';

class PhilIriCollection {
  final int? id;
  final int? schoolId;            // null = region-wide
  final String name;
  final String? description;
  final bool isPrescribed;        // DepEd-prescribed material
  final bool isGradeLeveled;      // passages carry a grade level (drives level stepping)
  final bool hasComprehension;    // passages come with comprehension questions
  /// Optional fixed order of selection numbers (e.g. FRB: 5,1,2,3,4,5,10,6,7,8,9,10).
  /// A number may repeat; each occurrence uses a different passage with that number.
  final List<int>? readingOrder;
  final bool isActive;
  final String? createdBy;        // users.id

  PhilIriCollection({
    this.id,
    this.schoolId,
    required this.name,
    this.description,
    this.isPrescribed = false,
    this.isGradeLeveled = true,
    this.hasComprehension = true,
    this.readingOrder,
    this.isActive = true,
    this.createdBy,
  });

  /// `reading_order` is a jsonb array in Postgres and a JSON string in SQLite.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'name': name,
        'description': description,
        'is_prescribed': isPrescribed,
        'is_grade_leveled': isGradeLeveled,
        'has_comprehension': hasComprehension,
        'reading_order': readingOrder,
        'is_active': isActive,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory PhilIriCollection.fromMap(Map<String, Object?> m) {
    final raw = m['reading_order'];
    final order = raw == null
        ? null
        : (raw is String ? jsonDecode(raw) as List : raw as List).cast<int>();
    return PhilIriCollection(
      id: m['id'] as int?,
      schoolId: m['school_id'] as int?,
      name: m['name'] as String,
      description: m['description'] as String?,
      isPrescribed: _bool(m['is_prescribed'], false),
      isGradeLeveled: _bool(m['is_grade_leveled'], true),
      hasComprehension: _bool(m['has_comprehension'], true),
      readingOrder: order,
      isActive: _bool(m['is_active'], true),
      createdBy: m['created_by'] as String?,
    );
  }
}

/// A rubric item a collection scores besides oral reading, e.g. the FLT
/// graphomotor section: "Spacing", 1–4.
class PhilIriRubricCriterion {
  final int? id;
  final int collectionId;
  final int criterionNo;          // display order, 1-based
  final String name;
  final int scaleMin;
  final int scaleMax;

  PhilIriRubricCriterion({
    this.id,
    required this.collectionId,
    required this.criterionNo,
    required this.name,
    this.scaleMin = 1,
    required this.scaleMax,
  });

  bool accepts(int score) => score >= scaleMin && score <= scaleMax;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'collection_id': collectionId,
        'criterion_no': criterionNo,
        'name': name,
        'scale_min': scaleMin,
        'scale_max': scaleMax,
      };

  factory PhilIriRubricCriterion.fromMap(Map<String, Object?> m) => PhilIriRubricCriterion(
        id: m['id'] as int?,
        collectionId: m['collection_id'] as int,
        criterionNo: m['criterion_no'] as int,
        name: m['name'] as String,
        scaleMin: m['scale_min'] as int,
        scaleMax: m['scale_max'] as int,
      );
}

/// Postgres returns bool, SQLite returns 0/1.
bool _bool(Object? v, bool fallback) =>
    v is bool ? v : (v == null ? fallback : (v as int) == 1);
