// lib/core/models/report_setting.dart
//
// One stored row of report_settings: the region-wide row (schoolId null,
// superadmin) or one school's override (its admin/coordinator). settings is a
// partial map; the effective values are the built-in defaults, then the
// region row, then the school row, key by key (as aral_settings).
// Keys: done_threshold (a share 0.01-1, default 0.85).
import 'dart:convert';

class ReportSetting {
  final int? id;
  final int? schoolId;                 // null = region-wide
  final Map<String, Object?> settings;
  final String? updatedBy;             // users.id, stamped by the database
  final String? updatedAt;

  ReportSetting({
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

  factory ReportSetting.fromMap(Map<String, Object?> m) {
    final raw = m['settings'];
    return ReportSetting(
      id: m['id'] as int?,
      schoolId: m['school_id'] as int?,
      // jsonb comes back decoded; SQLite holds a JSON string.
      settings: (raw is String ? jsonDecode(raw) : raw as Map).cast<String, Object?>(),
      updatedBy: m['updated_by'] as String?,
      updatedAt: m['updated_at'] as String?,
    );
  }
}

/// The report settings that apply to a school (defaults <- region <- school).
class ReportSettings {
  static const doneThresholdKey = 'done_threshold';
  static const defaultDoneThreshold = 0.85;

  /// Share of a section's enrolled learners that must be assessed in a round
  /// for the section to count as done (progress monitoring, reminders).
  final double doneThreshold;

  const ReportSettings({this.doneThreshold = defaultDoneThreshold});

  factory ReportSettings.fromMap(Map<String, Object?> m) => ReportSettings(
        doneThreshold: (m[doneThresholdKey] as num?)?.toDouble() ?? defaultDoneThreshold,
      );
}

/// A threshold share as a percent label: 0.85 -> "85%", 0.875 -> "87.5%".
String thresholdPercent(double share) {
  final p = (share * 1000).round() / 10;
  return '${p == p.roundToDouble() ? p.toInt() : p}%';
}
