// lib/viewmodels/reminder_viewmodel.dart
//
// Dashboard reminders (D2: coordinators; D3 adds tutors). Data the UI shows,
// not notifications. Per scheduled round of the school's calendar (D1):
//  * upcoming and opening within reminderHeadsUpDays -> heads-up;
//  * open -> in progress, with the sections still below the done threshold;
//  * closed with sections below the threshold -> overdue (closed and all done
//    -> nothing).
// Phil-IRI (Grade 4-10) completion is NlaReportViewModel.progress, the same
// definition of "done"; CRLA (Grade 1-3) counts the learners with a
// crla_results row of that round in the section, against the same threshold.
// The threshold is the saved report setting unless one is passed.
import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/report_setting.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/calendar_rules.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'report_settings_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
import 'viewmodel_exception.dart';

/// A round that has not opened yet gets a heads-up this many days before.
const reminderHeadsUpDays = 7;

/// In display order: overdue first, heads-up last.
enum ReminderKind { overdue, inProgress, headsUp }

/// One section's completion of a round (only sections with learners).
class SectionCompletion {
  final Section section;
  final int assessed;
  final int enrolled;

  /// At or above the done threshold.
  final bool done;

  const SectionCompletion(this.section, this.assessed, this.enrolled, this.done);

  double get share => assessed / enrolled;
}

class CoordinatorReminder {
  final int schoolId;
  final CalendarInstrument instrument;
  final CalendarWindow window;
  final ReminderKind kind;

  /// Days until opens_on (heads-up), until closes_on (in progress, 0 = closes
  /// today), or since closes_on (overdue).
  final int days;

  /// Sections of the instrument's grades with learners.
  final int sectionCount;

  /// Those still below [doneThreshold] (empty for a heads-up), by grade then name.
  final List<SectionCompletion> below;
  final double doneThreshold;

  const CoordinatorReminder(this.schoolId, this.instrument, this.window, this.kind, this.days, this.sectionCount,
      this.below, this.doneThreshold);

  String get roundName => '${instrument.label} ${roundLabel(window.round)}';

  String get message {
    String n(int d) => d == 1 ? '1 day' : '$d days';
    final pending = below.isEmpty
        ? (sectionCount == 1 ? 'the 1 section done' : 'all $sectionCount sections done')
        : '${below.length} of $sectionCount section${sectionCount == 1 ? '' : 's'} below '
            '${thresholdPercent(doneThreshold)}';
    return switch (kind) {
      ReminderKind.headsUp => '$roundName opens in ${n(days)} (${window.opensOn}).',
      ReminderKind.inProgress => '$roundName ${days == 0 ? 'closes today' : 'closes in ${n(days)}'}: $pending.',
      ReminderKind.overdue => '$roundName closed ${n(days)} ago: $pending.',
    };
  }
}

class SchoolReminders {
  final int schoolId;
  final String schoolName;
  final double doneThreshold;
  final List<CoordinatorReminder> reminders;

  const SchoolReminders(this.schoolId, this.schoolName, this.doneThreshold, this.reminders);
}

class ReminderViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final RoundCalendarViewModel _calendar;
  final NlaReportViewModel _reports;
  final ReportSettingsViewModel _reportSettings;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final StudentRepository _students;
  final CrlaResultRepository _crlaResults;

  ReminderViewModel({
    required AuthViewModel auth,
    required RoundCalendarViewModel calendar,
    required NlaReportViewModel reports,
    required ReportSettingsViewModel reportSettings,
    required SchoolRepository schools,
    required SectionRepository sections,
    required StudentRepository students,
    required CrlaResultRepository crlaResults,
    Logger? logger,
  })  : _auth = auth,
        _calendar = calendar,
        _reports = reports,
        _reportSettings = reportSettings,
        _schools = schools,
        _sections = sections,
        _students = students,
        _crlaResults = crlaResults,
        _log = ScopedLogger(logger, 'ReminderViewModel');

  /// Reminders for [schoolId]'s coordinators in [year] as of [today] (default
  /// now): admin/coordinator of the school, or the superadmin. [schoolId] null
  /// = every school on this device (superadmin only), ordered by name; a school
  /// without reminders is kept with an empty list. [doneThreshold] (a share)
  /// overrides the saved setting for this call only.
  Future<List<SchoolReminders>> coordinatorReminders(int? schoolId, String year,
      {DateTime? today, double? doneThreshold}) async {
    _log('coordinatorReminders($schoolId, $year, today: $today, done: $doneThreshold)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator sees coordinator reminders.');
    }
    if (me.schoolId != null && schoolId == null) {
      throw const ViewModelException('Forbidden: only the superadmin sees the reminders of every school.');
    }
    if (me.schoolId != null && schoolId != me.schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
    if (doneThreshold != null && !(doneThreshold > 0 && doneThreshold <= 1)) {
      throw ViewModelException('The done threshold is a share above 0 and up to 1 (got $doneThreshold).');
    }
    try {
      year = normalizeSchoolYear(year);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
    final day = today ?? DateTime.now();
    final schools = schoolId == null
        ? ((await _schools.getAll())..sort((a, b) => a.schoolName.compareTo(b.schoolName)))
        : [await _schools.getById(schoolId) ?? (throw ViewModelException('No school $schoolId on this device.'))];
    return [
      for (final s in schools) await _forSchool(s.id!, s.schoolName, year, day, doneThreshold),
    ];
  }

  Future<SchoolReminders> _forSchool(int schoolId, String name, String year, DateTime today, double? passed) async {
    final threshold = passed ?? (await _reportSettings.effective(schoolId)).doneThreshold;
    final out = <CoordinatorReminder>[];
    ProgressReport? progress; // computed once, only when a Phil-IRI round needs it
    for (final instrument in CalendarInstrument.values) {
      for (final entry in await _calendar.scheduledRounds(schoolId, year, instrument)) {
        final w = entry.window;
        final status = _calendar.status(w, today: today);
        final ReminderKind kind;
        final int days;
        switch (status) {
          case RoundStatus.upcoming:
            days = _daysBetween(calendarDate(today), w.opensOn!);
            if (days > reminderHeadsUpDays) continue;
            kind = ReminderKind.headsUp;
          case RoundStatus.open:
            days = _daysBetween(calendarDate(today), w.closesOn!);
            kind = ReminderKind.inProgress;
          case RoundStatus.closed:
            days = _daysBetween(w.closesOn!, calendarDate(today));
            kind = ReminderKind.overdue;
        }
        final List<SectionCompletion> all;
        if (instrument == CalendarInstrument.philIri) {
          progress ??= await _reports.progress(
              schoolId: schoolId, schoolYear: year, doneThreshold: threshold, asOf: today);
          final round = PhilIriRound.values.byName(w.round);
          all = [
            for (final r in progress.sections)
              if (r.enrolment.total > 0)
                SectionCompletion(r.section!, r.assessed[round]!.total, r.enrolment.total,
                    progress.status(r, round) == 'DONE'),
          ];
        } else {
          all = await _crlaCompletion(
              schoolId, year, CrlaRound.values.byName(w.round), calendarDate(today), threshold);
        }
        if (all.isEmpty) continue; // no sections of this instrument's grades
        final below = kind == ReminderKind.headsUp
            ? <SectionCompletion>[]
            : all.where((c) => !c.done).toList();
        if (kind == ReminderKind.overdue && below.isEmpty) continue;
        out.add(CoordinatorReminder(schoolId, instrument, w, kind, days, all.length, below, threshold));
      }
    }
    int order(CoordinatorReminder r) =>
        r.instrument.index * 100 + calendarRounds[r.instrument]!.indexOf(r.window.round);
    out.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      final d = a.kind == ReminderKind.overdue ? b.days.compareTo(a.days) : a.days.compareTo(b.days);
      return d != 0 ? d : order(a).compareTo(order(b));
    });
    return SchoolReminders(schoolId, name, threshold, out);
  }

  /// Per Grade 1-3 section of the school with learners: how many of its
  /// learners have a crla_results row of [round] in that section dated on or
  /// before [asOf] (several attempts count once); done as in progress
  /// monitoring (counts, not the rounded share).
  Future<List<SectionCompletion>> _crlaCompletion(
      int schoolId, String year, CrlaRound round, String asOf, double threshold) async {
    final sections = (await _sections.getAll()).where((s) {
      final g = int.tryParse(s.gradeLevel);
      return s.schoolId == schoolId && s.schoolYear == year && g != null && g >= 1 && g <= 3;
    }).toList()
      ..sort((a, b) {
        final g = int.parse(a.gradeLevel).compareTo(int.parse(b.gradeLevel));
        return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
      });
    final out = <SectionCompletion>[];
    for (final s in sections) {
      final learners = {for (final st in await _students.getBySection(s.id!)) st.id!};
      if (learners.isEmpty) continue;
      final assessed = {
        for (final r in await _crlaResults.getBySection(s.id!, schoolYear: year))
          if (r.round == round && learners.contains(r.studentId) && _day(r.assessedAt).compareTo(asOf) <= 0)
            r.studentId,
      };
      out.add(SectionCompletion(
          s, assessed.length, learners.length, assessed.length >= threshold * learners.length - 1e-9));
    }
    return out;
  }

  static String _day(String timestamp) => timestamp.length >= 10 ? timestamp.substring(0, 10) : timestamp;

  /// Whole days from [from] to [to] (both YYYY-MM-DD).
  static int _daysBetween(String from, String to) =>
      DateTime.utc(int.parse(to.substring(0, 4)), int.parse(to.substring(5, 7)), int.parse(to.substring(8, 10)))
          .difference(DateTime.utc(
              int.parse(from.substring(0, 4)), int.parse(from.substring(5, 7)), int.parse(from.substring(8, 10))))
          .inDays;
}
