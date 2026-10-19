// lib/core/models/aral_setting.dart
//
// One stored row of aral_settings: the region-wide row (schoolId null,
// superadmin) or one school's override (its admin/coordinator). settings is a
// partial map; the effective values are the built-in defaults, then the
// region row, then the school row, key by key (as crla_thresholds).
// Keys: checkin_pass_pct (1-100, default 75), foundational_program (bool,
// default off), idle_session_days (1-60, default 7).
import 'dart:convert';

class AralSetting {
  final int? id;
  final int? schoolId;                 // null = region-wide
  final Map<String, Object?> settings;
  final String? updatedBy;             // users.id, stamped by the database
  final String? updatedAt;

  AralSetting({
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

  factory AralSetting.fromMap(Map<String, Object?> m) {
    final raw = m['settings'];
    return AralSetting(
      id: m['id'] as int?,
      schoolId: m['school_id'] as int?,
      // jsonb comes back decoded; SQLite holds a JSON string.
      settings: (raw is String ? jsonDecode(raw) : raw as Map).cast<String, Object?>(),
      updatedBy: m['updated_by'] as String?,
      updatedAt: m['updated_at'] as String?,
    );
  }
}
