// lib/core/models/report_setting.dart
//
// One stored row of report_settings: the region-wide row (schoolId null,
// superadmin) or one school's override (its admin/coordinator). settings is a
// partial map; the effective values are the built-in defaults, then the
// region row, then the school row, key by key (as aral_settings).
// Keys: done_threshold (a share 0.01-1, default 0.85), offline_signin_days
// (whole days 1-60, default 14; sync spec 2.4), sync_auto_approve (bool,
// default false; sync S6), no_comprehension_counts_FLT (bool, default false;
// owner 2026-11-10: a Phil-IRI reading from a collection without
// comprehension questions, e.g. the FLT, counts as assessed),
// archive_keep_months (whole months 1-120, default 6; SF1 leavers D12: how
// long an archived learner is kept before they may be anonymized), and the
// six Phil-IRI value switches values_aral, values_bosy_masterlist,
// values_form2b, values_srp, values_learner_pages (default "carried") and
// values_ranking (default "actual"): "carried" | "actual", which Phil-IRI
// values a list shows (spec 2026-11-14 value sources D1-D3; anything else
// stored reads as the key's default).
import 'dart:convert';

/// Which Phil-IRI values a list shows: carried (the best so far, carried
/// into later rounds) or actual (each round's own reading). [name] is the
/// stored string.
enum PhilIriValues { carried, actual }

/// The lists a school switches between carried and actual values, with
/// their report_settings key, console name and default.
enum PhilIriValueList {
  aral('values_aral', 'aral', PhilIriValues.carried),
  bosyMasterlist('values_bosy_masterlist', 'bosy-masterlist', PhilIriValues.carried),
  form2b('values_form2b', 'form2b', PhilIriValues.carried),
  srp('values_srp', 'srp', PhilIriValues.carried),
  learnerPages('values_learner_pages', 'learner-pages', PhilIriValues.carried),
  ranking('values_ranking', 'ranking', PhilIriValues.actual);

  final String key;
  final String cliName;
  final PhilIriValues defaultValue;
  const PhilIriValueList(this.key, this.cliName, this.defaultValue);

  /// The stored value, or null when [raw] is anything but "carried" /
  /// "actual" (a missing key, a typo, another type).
  static PhilIriValues? parse(Object? raw) {
    for (final v in PhilIriValues.values) {
      if (raw == v.name) return v;
    }
    return null;
  }
}

/// The header line a list prints for its values.
String philIriValuesLabel(PhilIriValues v) => switch (v) {
      PhilIriValues.carried => 'Values: carried (best so far)',
      PhilIriValues.actual => "Values: actual (each round's own reading)",
    };

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
  static const offlineSigninDaysKey = 'offline_signin_days';
  static const defaultOfflineSigninDays = 14;
  static const syncAutoApproveKey = 'sync_auto_approve';
  static const noComprehensionCountsFltKey = 'no_comprehension_counts_FLT';
  static const minOfflineSigninDays = 1;
  static const maxOfflineSigninDays = 60;
  static const archiveKeepMonthsKey = 'archive_keep_months';
  static const defaultArchiveKeepMonths = 6;
  static const minArchiveKeepMonths = 1;
  static const maxArchiveKeepMonths = 120;

  /// Share of a section's enrolled learners that must be assessed in a round
  /// for the section to count as done (progress monitoring, reminders).
  final double doneThreshold;

  /// Days after the last online sign-in during which the device owner may
  /// sign in offline.
  final int offlineSigninDays;

  /// Uploads from this school's tutors apply without an approver (sync).
  final bool syncAutoApprove;

  /// A Phil-IRI reading from a collection without comprehension questions
  /// (the FLT) counts as assessed with words read and time alone (progress,
  /// reminders, dashboard). Off: assessed needs a comprehension entry.
  final bool noComprehensionCountsFlt;

  /// Months an archived learner is kept before they may be anonymized (the
  /// server's learner_anonymize_eligible reads the same key).
  final int archiveKeepMonths;

  /// Which Phil-IRI values each list shows (every list present).
  final Map<PhilIriValueList, PhilIriValues> valueSources;

  /// The values [list] shows.
  PhilIriValues valueSource(PhilIriValueList list) => valueSources[list] ?? list.defaultValue;

  /// Every list at its default (keep in step with [PhilIriValueList]).
  static const Map<PhilIriValueList, PhilIriValues> defaultValueSources = {
    PhilIriValueList.aral: PhilIriValues.carried,
    PhilIriValueList.bosyMasterlist: PhilIriValues.carried,
    PhilIriValueList.form2b: PhilIriValues.carried,
    PhilIriValueList.srp: PhilIriValues.carried,
    PhilIriValueList.learnerPages: PhilIriValues.carried,
    PhilIriValueList.ranking: PhilIriValues.actual,
  };

  const ReportSettings({
    this.doneThreshold = defaultDoneThreshold,
    this.offlineSigninDays = defaultOfflineSigninDays,
    this.syncAutoApprove = false,
    this.noComprehensionCountsFlt = false,
    this.archiveKeepMonths = defaultArchiveKeepMonths,
    Map<PhilIriValueList, PhilIriValues>? valueSources,
  }) : valueSources = valueSources ?? defaultValueSources;

  factory ReportSettings.fromMap(Map<String, Object?> m) => ReportSettings(
        doneThreshold: (m[doneThresholdKey] as num?)?.toDouble() ?? defaultDoneThreshold,
        offlineSigninDays: (m[offlineSigninDaysKey] as num?)?.toInt() ?? defaultOfflineSigninDays,
        syncAutoApprove: m[syncAutoApproveKey] == true,
        noComprehensionCountsFlt: m[noComprehensionCountsFltKey] == true,
        archiveKeepMonths: (m[archiveKeepMonthsKey] as num?)?.toInt() ?? defaultArchiveKeepMonths,
        valueSources: Map.unmodifiable(
            {for (final l in PhilIriValueList.values) l: PhilIriValueList.parse(m[l.key]) ?? l.defaultValue}),
      );
}

/// A threshold share as a percent label: 0.85 -> "85%", 0.875 -> "87.5%".
String thresholdPercent(double share) {
  final p = (share * 1000).round() / 10;
  return '${p == p.roundToDouble() ? p.toInt() : p}%';
}
