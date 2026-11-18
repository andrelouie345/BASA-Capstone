// lib/core/services/aral_rule_settings.dart
//
// The ARAL rules that DepEd (or a Division) sets by memo, as school settings
// (keys of aral_settings.settings; built-in defaults <- region row <- school
// row). Every default is the behaviour BASA had before the settings existed
// (DepEd Memorandum 064 s. 2025), so a school that sets nothing sees no
// change. Spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md
// (Division Memorandum 180 s. 2026, Schools Division of Valencia City):
//  * class_max_learners 1-50 (default 15) and class_min_learners 0-50
//    (0 = none; never above the maximum: an inconsistent minimum is ignored);
//  * session_max_minutes 1-120 (absent = today: warn above 60 on weekdays,
//    refuse above 120); sessions_weekdays_only (default off);
//    class_min_sessions_per_week 0-7 (0 = no reminder);
//  * basis_round bosy | mosy (default bosy): the round new ARAL learners
//    are chosen from;
//  * checkin_after_sessions [first, second], increasing, 1-200 (default
//    [16, 32]): when the two check-ins are due. Tools and saved check-ins
//    keep their checkpoint ids 16 and 32 (= first, second);
//  * irip_weeks 1-26 (default 8): the length of an IRIP cycle.
// The same keys and ranges are checked by the cloud (aral_settings CHECK
// constraints, migration 20261118010000).
library;

/// The round new ARAL learners are chosen from.
enum AralBasisRound {
  bosy('bosy'),
  mosy('mosy');

  final String value;
  const AralBasisRound(this.value);

  static AralBasisRound? tryParse(Object? v) => AralBasisRound.values.where((r) => r.value == v).firstOrNull;
}

class AralRuleSettings {
  static const classMaxLearnersKey = 'class_max_learners';
  static const classMinLearnersKey = 'class_min_learners';
  static const sessionMaxMinutesKey = 'session_max_minutes';
  static const sessionsWeekdaysOnlyKey = 'sessions_weekdays_only';
  static const classMinSessionsPerWeekKey = 'class_min_sessions_per_week';
  static const basisRoundKey = 'basis_round';
  static const checkinAfterSessionsKey = 'checkin_after_sessions';
  static const iripWeeksKey = 'irip_weeks';

  /// Every key, in the order the console lists them.
  static const keys = [
    classMaxLearnersKey,
    classMinLearnersKey,
    sessionMaxMinutesKey,
    sessionsWeekdaysOnlyKey,
    classMinSessionsPerWeekKey,
    basisRoundKey,
    checkinAfterSessionsKey,
    iripWeeksKey,
  ];

  /// The check-in checkpoint ids the tools and saved check-ins use (first,
  /// second check-in).
  static const checkpointIds = [16, 32];

  static const defaults = AralRuleSettings(
    classMaxLearners: 15,
    classMinLearners: 0,
    sessionMaxMinutes: null,
    sessionsWeekdaysOnly: false,
    classMinSessionsPerWeek: 0,
    basisRound: AralBasisRound.bosy,
    checkinAfterSessions: [16, 32],
    iripWeeks: 8,
  );

  final int classMaxLearners;
  final int classMinLearners;          // 0 = none
  final int? sessionMaxMinutes;        // null = today's rule
  final bool sessionsWeekdaysOnly;
  final int classMinSessionsPerWeek;   // 0 = no reminder
  final AralBasisRound basisRound;
  final List<int> checkinAfterSessions; // [first, second]
  final int iripWeeks;

  const AralRuleSettings({
    required this.classMaxLearners,
    required this.classMinLearners,
    required this.sessionMaxMinutes,
    required this.sessionsWeekdaysOnly,
    required this.classMinSessionsPerWeek,
    required this.basisRound,
    required this.checkinAfterSessions,
    required this.iripWeeks,
  });

  /// Defaults, then [m]'s keys; unknown keys and bad values are ignored, and
  /// a minimum above the maximum is ignored.
  factory AralRuleSettings.fromMap(Map<String, Object?> m) {
    T pick<T>(String key, T fallback) => aralRuleSettingProblem(key, m[key]) == null ? _typed(key, m[key]) as T : fallback;
    final max = pick(classMaxLearnersKey, defaults.classMaxLearners);
    final min = pick(classMinLearnersKey, defaults.classMinLearners);
    return AralRuleSettings(
      classMaxLearners: max,
      classMinLearners: min <= max ? min : defaults.classMinLearners,
      sessionMaxMinutes: pick<int?>(sessionMaxMinutesKey, defaults.sessionMaxMinutes),
      sessionsWeekdaysOnly: pick(sessionsWeekdaysOnlyKey, defaults.sessionsWeekdaysOnly),
      classMinSessionsPerWeek: pick(classMinSessionsPerWeekKey, defaults.classMinSessionsPerWeek),
      basisRound: pick(basisRoundKey, defaults.basisRound),
      checkinAfterSessions: pick(checkinAfterSessionsKey, defaults.checkinAfterSessions),
      iripWeeks: pick(iripWeeksKey, defaults.iripWeeks),
    );
  }

  /// The stored value of [key] as it is held here (for listings).
  Object? valueOf(String key) => switch (key) {
        classMaxLearnersKey => classMaxLearners,
        classMinLearnersKey => classMinLearners,
        sessionMaxMinutesKey => sessionMaxMinutes,
        sessionsWeekdaysOnlyKey => sessionsWeekdaysOnly,
        classMinSessionsPerWeekKey => classMinSessionsPerWeek,
        basisRoundKey => basisRound.value,
        checkinAfterSessionsKey => checkinAfterSessions,
        iripWeeksKey => iripWeeks,
        _ => throw ArgumentError('Unknown ARAL setting "$key"'),
      };
}

/// A valid [value] of [key] in this class's types (only called after
/// [aralRuleSettingProblem] said it is valid).
Object? _typed(String key, Object? value) => switch (key) {
      AralRuleSettings.basisRoundKey => AralBasisRound.tryParse(value),
      AralRuleSettings.checkinAfterSessionsKey => [for (final v in value as List) (v as num).toInt()],
      AralRuleSettings.sessionsWeekdaysOnlyKey => value,
      _ => (value as num).toInt(),
    };

bool _wholeIn(Object? v, int lo, int hi) => v is num && v == v.roundToDouble() && v >= lo && v <= hi;

/// Null when [value] is valid for [key], else a plain message (the same
/// ranges as the cloud's aral_settings CHECK constraints). The minimum
/// against the maximum is checked by the ViewModel, which knows both.
String? aralRuleSettingProblem(String key, Object? value) => switch (key) {
      AralRuleSettings.classMaxLearnersKey =>
        _wholeIn(value, 1, 50) ? null : 'The class maximum is a whole number 1-50, not $value.',
      AralRuleSettings.classMinLearnersKey =>
        _wholeIn(value, 0, 50) ? null : 'The class minimum is a whole number 0-50 (0 = none), not $value.',
      AralRuleSettings.sessionMaxMinutesKey =>
        _wholeIn(value, 1, 120) ? null : 'The longest session is 1-120 minutes, not $value.',
      AralRuleSettings.sessionsWeekdaysOnlyKey =>
        value is bool ? null : 'Weekdays only is on or off (true/false), not $value.',
      AralRuleSettings.classMinSessionsPerWeekKey =>
        _wholeIn(value, 0, 7) ? null : 'The sessions a week are a whole number 0-7 (0 = no reminder), not $value.',
      AralRuleSettings.basisRoundKey =>
        AralBasisRound.tryParse(value) != null ? null : 'The basis round is bosy or mosy, not $value.',
      AralRuleSettings.checkinAfterSessionsKey => value is List &&
              value.length == 2 &&
              value.every((v) => _wholeIn(v, 1, 200)) &&
              (value[0] as num) < (value[1] as num)
          ? null
          : 'The check-ins come after two sessions, the first before the second, each 1-200 (e.g. 16,32), not $value.',
      AralRuleSettings.iripWeeksKey =>
        _wholeIn(value, 1, 26) ? null : 'An IRIP cycle has 1-26 weeks, not $value.',
      _ => 'Unknown ARAL setting "$key". The settings are: ${AralRuleSettings.keys.join(', ')}.',
    };

/// The check-in checkpoint id (16 = first, 32 = second) due after the class's
/// session [sessionNo], or 0 when no check-in is due after it.
int aralCheckpointForSession(AralRuleSettings s, int sessionNo) {
  final i = s.checkinAfterSessions.indexOf(sessionNo);
  return i < 0 ? 0 : AralRuleSettings.checkpointIds[i];
}

/// [text] as a value of [key] (console and text fields): whole numbers,
/// `on`/`off`/`true`/`false`, `bosy`/`mosy`, and `16,32` for the check-in
/// sessions. Returns the text unchanged when it doesn't parse, so
/// [aralRuleSettingProblem] names what is wrong.
Object? aralRuleSettingFromText(String key, String text) {
  final t = text.trim();
  switch (key) {
    case AralRuleSettings.sessionsWeekdaysOnlyKey:
      return switch (t.toLowerCase()) { 'on' || 'true' => true, 'off' || 'false' => false, _ => t };
    case AralRuleSettings.basisRoundKey:
      return t.toLowerCase();
    case AralRuleSettings.checkinAfterSessionsKey:
      final parts = t.split(',').map((p) => int.tryParse(p.trim())).toList();
      return parts.contains(null) ? t : parts.cast<int>();
    default:
      return int.tryParse(t) ?? t;
  }
}
