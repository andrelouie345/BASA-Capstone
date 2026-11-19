// ARAL memo settings (spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md
// section 1): every key defaults to today's behaviour; bad stored values are
// ignored on read and refused on write.
import 'package:basa_capstone/core/services/aral_rule_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("defaults keep today's behaviour", () {
    final s = AralRuleSettings.fromMap({});
    expect(s.classMaxLearners, 15);
    expect(s.classMinLearners, 0);
    expect(s.sessionMaxMinutes, isNull);
    expect(s.sessionsWeekdaysOnly, isFalse);
    expect(s.classMinSessionsPerWeek, 0);
    expect(s.basisRound, AralBasisRound.bosy);
    expect(s.checkinAfterSessions, [16, 32]);
    expect(s.iripWeeks, 8);
  });

  test('school values over defaults', () {
    final s = AralRuleSettings.fromMap({
      'class_max_learners': 10,
      'class_min_learners': 5,
      'sessions_weekdays_only': true,
      'session_max_minutes': 60,
      'basis_round': 'mosy',
      'class_min_sessions_per_week': 3,
      'checkin_after_sessions': [12, 24],
      'irip_weeks': 6,
    });
    expect(s.classMaxLearners, 10);
    expect(s.classMinLearners, 5);
    expect(s.sessionsWeekdaysOnly, isTrue);
    expect(s.sessionMaxMinutes, 60);
    expect(s.basisRound, AralBasisRound.mosy);
    expect(s.classMinSessionsPerWeek, 3);
    expect(s.checkinAfterSessions, [12, 24]);
    expect(s.iripWeeks, 6);
  });

  test('bad values fall back', () {
    expect(AralRuleSettings.fromMap({'class_max_learners': '10'}).classMaxLearners, 15);
    expect(AralRuleSettings.fromMap({'class_max_learners': 10.5}).classMaxLearners, 15);
    expect(AralRuleSettings.fromMap({'session_max_minutes': 121}).sessionMaxMinutes, isNull);
    expect(AralRuleSettings.fromMap({'checkin_after_sessions': [32, 16]}).checkinAfterSessions, [16, 32]);
    expect(AralRuleSettings.fromMap({'checkin_after_sessions': [16]}).checkinAfterSessions, [16, 32]);
    expect(AralRuleSettings.fromMap({'irip_weeks': 0}).iripWeeks, 8);
    expect(AralRuleSettings.fromMap({'basis_round': 'eosy'}).basisRound, AralBasisRound.bosy);
    expect(AralRuleSettings.fromMap({'class_max_learners': 10, 'class_min_learners': 12}).classMinLearners, 0);
  });

  test('problems name the range', () {
    expect(aralRuleSettingProblem('class_max_learners', 0), contains('1-50'));
    expect(aralRuleSettingProblem('class_max_learners', 10), isNull);
    expect(aralRuleSettingProblem('session_max_minutes', 150), contains('120'));
    expect(aralRuleSettingProblem('basis_round', 'eosy'), isNotNull);
    expect(aralRuleSettingProblem('basis_round', 'mosy'), isNull);
    expect(aralRuleSettingProblem('checkin_after_sessions', [24, 12]), isNotNull);
    expect(aralRuleSettingProblem('checkin_after_sessions', [24, 12]), endsWith('not 24,12.')); // as typed, not a Dart list
    expect(aralRuleSettingProblem('checkin_after_sessions', [12, 24]), isNull);
    expect(aralRuleSettingProblem('sessions_weekdays_only', 'yes'), isNotNull);
    expect(aralRuleSettingProblem('nope', 1), contains('class_max_learners'));
  });

  test('typed text as a value', () {
    expect(aralRuleSettingFromText('class_max_learners', ' 10 '), 10);
    expect(aralRuleSettingFromText('sessions_weekdays_only', 'on'), isTrue);
    expect(aralRuleSettingFromText('sessions_weekdays_only', 'OFF'), isFalse);
    expect(aralRuleSettingFromText('basis_round', 'MoSY'), 'mosy');
    expect(aralRuleSettingFromText('checkin_after_sessions', '12, 24'), [12, 24]);
    expect(aralRuleSettingFromText('checkin_after_sessions', '12,x'), '12,x');
    expect(aralRuleSettingFromText('irip_weeks', 'six'), 'six');
  });

  test('checkpoint for a session', () {
    final s = AralRuleSettings.fromMap({'checkin_after_sessions': [12, 24]});
    expect(aralCheckpointForSession(s, 12), 16);
    expect(aralCheckpointForSession(s, 24), 32);
    expect(aralCheckpointForSession(s, 16), 0);
    expect(aralCheckpointForSession(AralRuleSettings.defaults, 32), 32);
  });
}
