// lib/core/models/phil_iri_threshold_setting.dart
//
// One stored row of phil_iri_thresholds: the region-wide row (schoolId null,
// superadmin) or one school's override (its admin/coordinator). settings is a
// partial or full PhilIriThresholds.toMap(); the effective values are the
// built-in defaults, then the region row, then the school row, key by key:
//   PhilIriThresholds.fromMap({...?region?.settings, ...?school?.settings})
import 'dart:convert';

class PhilIriThresholdSetting {
  final int? id;
  final int? schoolId;                 // null = region-wide
  final Map<String, Object?> settings;
  final String? updatedBy;             // users.id, stamped by the database
  final String? updatedAt;

  PhilIriThresholdSetting({
    this.id,
    this.schoolId,
    required this.settings,
    this.updatedBy,
    this.updatedAt,
  });

  /// updated_by / updated_at are stamped by the database, never sent.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'settings': settings,
      };

  factory PhilIriThresholdSetting.fromMap(Map<String, Object?> m) {
    final raw = m['settings'];
    return PhilIriThresholdSetting(
      id: m['id'] as int?,
      schoolId: m['school_id'] as int?,
      // jsonb comes back decoded; SQLite holds a JSON string.
      settings: (raw is String ? jsonDecode(raw) : raw as Map).cast<String, Object?>(),
      updatedBy: m['updated_by'] as String?,
      updatedAt: m['updated_at'] as String?,
    );
  }
}
