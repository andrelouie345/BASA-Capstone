// lib/viewmodels/aral_checkin_viewmodel.dart
//
// ARAL-Reading check-in assessments (piece CI3). Check-ins are offline-first:
// they are read and written in the local copy, like the IRIP. The cut-off is
// managed online and mirrored locally, like the CRLA thresholds.
//
// Owner decisions (2026-10-16):
//  * One tool per key stage, track and checkpoint (after session 16 / 32);
//    KS1 and Foundational have none.
//  * Per-item marks: choice items take the learner's letter and are scored by
//    the database; open items take the tutor's right/wrong mark.
//  * Retakes allowed (attempt_no per learner and tool; the latest counts).
//  * Pass = at least the cut-off percentage (default 75), overall and per
//    part, judged when read: changing the cut-off re-judges old check-ins.
//  * Record and report only: nothing here changes the IRIP, placement or exit.
//  * The learner's ARAL tutor and the school's admins/coordinators record
//    check-ins; the cut-off: region = superadmin, a school's override = that
//    school's admin/coordinator.
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/aral_checkin.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_setting.dart';
import '../core/models/section.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_checkin_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/aral_checkin_rules.dart';
import '../core/services/aral_rules.dart' show AralProgramSettings, AralSessionSettings;
import '../core/services/csv.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

/// One check-in with its tool, items, answers and score.
class AralCheckinResult {
  final AralCheckin checkin;
  final AralCheckinTool tool;
  final List<AralCheckinItem> items;
  final Map<int, AralCheckinAnswer> answerByItem; // item id -> answer
  final AralCheckinScoring scoring;
  final int passPct;                              // the cut-off that applies today

  const AralCheckinResult({
    required this.checkin,
    required this.tool,
    required this.items,
    required this.answerByItem,
    required this.scoring,
    required this.passPct,
  });

  AralCheckinScore get score => scoring.overall;
  bool get passed => score.passes(passPct);
  bool get complete => scoring.complete;
}

/// A learner's check-ins and the tools of their current program.
class AralLearnerCheckins {
  final AralEnrollment enrollment;
  final Map<int, AralCheckinTool> toolsByCheckpoint; // 16 / 32 -> tool; empty for KS1/Foundational
  final List<AralCheckinResult> results;            // by tool, then attempt

  const AralLearnerCheckins(this.enrollment, this.toolsByCheckpoint, this.results);

  /// The latest attempt at [toolId], or null.
  AralCheckinResult? latest(int toolId) =>
      results.where((r) => r.tool.id == toolId).fold<AralCheckinResult?>(
          null, (best, r) => best == null || r.checkin.attemptNo > best.checkin.attemptNo ? r : best);

  /// The latest check-in after session [checkpoint] (any tool of that
  /// checkpoint), as the check-in report picks it; null when not taken.
  AralCheckinResult? latestAt(int checkpoint) =>
      aralLatestCheckin(results.where((r) => r.tool.checkpoint == checkpoint));
}

/// The latest of [results] (one checkpoint): latest date, then highest
/// attempt. Attempt numbers count per tool, so after a program change the
/// date decides. Shared by the check-in report and the learner history.
AralCheckinResult? aralLatestCheckin(Iterable<AralCheckinResult> results) {
  AralCheckinResult? latest;
  for (final r in results) {
    final c = r.checkin;
    if (latest == null ||
        c.takenOn.compareTo(latest.checkin.takenOn) > 0 ||
        (c.takenOn == latest.checkin.takenOn && c.attemptNo > latest.checkin.attemptNo)) {
      latest = r;
    }
  }
  return latest;
}

/// One learner of the check-in report: the latest attempt after session 16
/// and after session 32 (any tool of that checkpoint, in case the program
/// changed), null when not taken.
class AralCheckinReportLearner {
  final AralEnrollment enrollment;
  final String name;
  final AralCheckinResult? after16;
  final AralCheckinResult? after32;
  const AralCheckinReportLearner(this.enrollment, this.name, this.after16, this.after32);

  AralCheckinResult? at(int checkpoint) => checkpoint == 16 ? after16 : after32;

  /// KS1 and Foundational have no check-in tools.
  bool get hasTools => enrollment.track != null;
}

/// One section of the check-in report, with its totals.
class AralCheckinReportSection {
  final Section section;
  final List<AralCheckinReportLearner> learners;
  const AralCheckinReportSection(this.section, this.learners);

  int took(int checkpoint) => learners.where((l) => l.at(checkpoint) != null).length;
  int met(int checkpoint) => learners.where((l) => l.at(checkpoint)?.passed ?? false).length;
  /// Learners who have check-in tools (KS2-3).
  int get withTools => learners.where((l) => l.hasTools).length;
}

class AralCheckinReport {
  final int schoolId;
  final String schoolYear;
  final int passPct;
  final List<AralCheckinReportSection> sections;
  const AralCheckinReport(this.schoolId, this.schoolYear, this.passPct, this.sections);

  int took(int checkpoint) => sections.fold(0, (n, s) => n + s.took(checkpoint));
  int met(int checkpoint) => sections.fold(0, (n, s) => n + s.met(checkpoint));
}

/// The stored cut-off rows that apply to one school and their merge.
class AralCheckinSettingLayers {
  final AralSetting? region;
  final AralSetting? school;
  final AralCheckinSettings effective;
  const AralCheckinSettingLayers(this.region, this.school, this.effective);

  /// The values when nothing is stored.
  AralCheckinSettings get defaults => AralCheckinSettings.defaults;
}

class AralCheckinViewModel {
  static const _dbRefusals = [
    'The learner is not active in ARAL',
    "That check-in tool is not for the learner's ARAL program",
    'A check-in cannot be dated before the learner entered ARAL',
    'A check-in keeps its learner, tool and attempt; only the date and notes change',
    'A multiple-choice answer is a letter A-E (or empty)',
    "That item is not on the check-in's tool",
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralCheckinRepository _checkins;
  final AralEnrollmentRepository _roster;
  final AralSettingRepository _localSettings;
  final AralSettingRepository Function(SupabaseClient client) _cloudSettingsFor;
  final SectionRepository _sections;
  final StudentRepository _students;

  /// Set when the last cut-off change reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  AralCheckinViewModel({
    required AuthViewModel auth,
    required AralCheckinRepository checkins,
    required AralEnrollmentRepository roster,
    required AralSettingRepository localSettings,
    required AralSettingRepository Function(SupabaseClient client) cloudSettings,
    required SectionRepository sections,
    required StudentRepository students,
    Logger? logger,
  })  : _auth = auth,
        _checkins = checkins,
        _roster = roster,
        _localSettings = localSettings,
        _cloudSettingsFor = cloudSettings,
        _sections = sections,
        _students = students,
        _log = ScopedLogger(logger, 'AralCheckinViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Reading ----

  Future<List<AralCheckinTool>> tools() async {
    _requireSignIn();
    return _checkins.tools();
  }

  Future<List<AralCheckinItem>> items(int toolId) async {
    _requireSignIn();
    return _checkins.items(toolId);
  }

  /// The learner's check-ins ([enrollmentId] = ARAL enrollment id), scored
  /// with today's cut-off for the learner's school.
  Future<AralLearnerCheckins> learnerCheckins(int enrollmentId) async {
    _requireSignIn();
    _log('learnerCheckins($enrollmentId)');
    final e = await _require(enrollmentId);
    final tools = <int, AralCheckinTool>{};
    if (e.track != null) {
      for (final cp in aralCheckinCheckpoints) {
        final t = await _checkins.toolFor(e.keyStage, e.track!, cp);
        if (t != null) tools[cp] = t;
      }
    }
    final passPct = (await localSettings(e.schoolId)).passPct;
    final results = <AralCheckinResult>[];
    for (final c in await _checkins.checkins(e.id!)) {
      results.add(await _result(c, passPct));
    }
    return AralLearnerCheckins(e, tools, results);
  }

  /// One check-in, scored with today's cut-off.
  Future<AralCheckinResult> result(int checkinId) async {
    _requireSignIn();
    _log('result($checkinId)');
    final (c, e) = await _requireCheckin(checkinId);
    return _result(c, (await localSettings(e.schoolId)).passPct);
  }

  Future<AralCheckinResult> _result(AralCheckin c, int passPct) async {
    final tool = await _checkins.findTool(c.toolId);
    if (tool == null) throw ViewModelException('Check-in tool ${c.toolId} is not on this device. Download the latest data (pull-cloud).');
    final items = await _checkins.items(tool.id);
    final answers = await _checkins.answers(c.id!);
    return AralCheckinResult(
      checkin: c,
      tool: tool,
      items: items,
      answerByItem: {for (final a in answers) a.itemId: a},
      scoring: aralCheckinScore(items, answers),
      passPct: passPct,
    );
  }

  // ---- Report ----

  /// Every section of the school with ARAL learners in [schoolYear] ([sectionId]
  /// narrows it to one section): each learner's latest check-in after session
  /// 16 and 32, judged with today's cut-off, and per-section totals.
  /// Admins/coordinators only (their own school; superadmin any).
  Future<AralCheckinReport> checkinReport({required int schoolId, required String schoolYear, int? sectionId}) async {
    _requireSignIn();
    _log('checkinReport(school: $schoolId, year: $schoolYear, section: $sectionId)');
    final me = _me();
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can generate ARAL reports.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
    schoolYear = normalizeSchoolYear(schoolYear);
    final passPct = (await localSettings(schoolId)).passPct;

    final roster = (await _roster.getBySchool(schoolId, schoolYear: schoolYear))
        .where((e) => sectionId == null || e.sectionId == sectionId)
        .toList();
    final bySection = <int, List<AralEnrollment>>{};
    for (final e in roster) {
      bySection.putIfAbsent(e.sectionId, () => []).add(e);
    }
    final sections = <Section>[];
    for (final id in {...bySection.keys, ?sectionId}) {
      final s = await _sections.getById(id);
      if (s == null || s.schoolId != schoolId) {
        if (id == sectionId) throw ViewModelException('Section $sectionId is not a section of school $schoolId.');
        continue;
      }
      sections.add(s);
    }
    sections.sort((a, b) {
      final g = (int.tryParse(a.gradeLevel) ?? 0).compareTo(int.tryParse(b.gradeLevel) ?? 0);
      return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
    });

    final out = <AralCheckinReportSection>[];
    for (final s in sections) {
      final names = {
        for (final st in await _students.getBySection(s.id!)) st.id: '${st.lastName}, ${st.firstName}',
      };
      final learners = <AralCheckinReportLearner>[];
      for (final e in bySection[s.id] ?? const <AralEnrollment>[]) {
        final results = [for (final c in await _checkins.checkins(e.id!)) await _result(c, passPct)];
        AralCheckinResult? at(int checkpoint) => aralLatestCheckin(results.where((r) => r.tool.checkpoint == checkpoint));
        learners.add(AralCheckinReportLearner(e, names[e.studentId] ?? 'student ${e.studentId}', at(16), at(32)));
      }
      learners.sort((a, b) => a.name.compareTo(b.name));
      out.add(AralCheckinReportSection(s, learners));
    }
    return AralCheckinReport(schoolId, schoolYear, passPct, out);
  }

  /// [checkinReport] as CSV: one line per learner.
  Future<String> checkinReportCsv({required int schoolId, required String schoolYear, int? sectionId}) async {
    _requireSignIn();
    final r = await checkinReport(schoolId: schoolId, schoolYear: schoolYear, sectionId: sectionId);
    List<Object?> cells(AralCheckinResult? x) => x == null
        ? ['', '', '', '', '']
        : [x.checkin.takenOn, x.checkin.attemptNo, '${x.score.correct}/${x.score.total}',
           x.score.percent.toStringAsFixed(0), '${x.passed ? 'Met' : 'Not met'}${x.complete ? '' : ' (incomplete)'}'];
    return csvTable([
      [
        'Grade', 'Section', 'Learner', 'Program', 'Status',
        'After 16: date', 'After 16: attempt', 'After 16: score', 'After 16: %', 'After 16: result',
        'After 32: date', 'After 32: attempt', 'After 32: score', 'After 32: %', 'After 32: result',
        'Cut-off %', 'ARAL id',
      ],
      for (final s in r.sections)
        for (final l in s.learners)
          [
            s.section.gradeLevel, s.section.sectionName, l.name, l.enrollment.programLabel,
            l.enrollment.isActive ? 'active' : 'exited',
            ...(l.hasTools ? cells(l.after16) : ['no check-in tools', '', '', '', '']),
            ...(l.hasTools ? cells(l.after32) : ['', '', '', '', '']),
            r.passPct, l.enrollment.id,
          ],
    ]);
  }

  // ---- Writing ----

  /// Records an attempt at the check-in after session [checkpoint] (16 or 32)
  /// of the learner's current program, taken [on] (default today).
  Future<AralCheckin> startCheckin(int enrollmentId, int checkpoint, {DateTime? on, String? notes}) async {
    _requireSignIn();
    _log('startCheckin($enrollmentId, $checkpoint)');
    if (!aralCheckinCheckpoints.contains(checkpoint)) {
      throw ViewModelException('A check-in comes after session 16 or 32, not $checkpoint.');
    }
    final e = await _require(enrollmentId);
    if (e.track == null) {
      throw ViewModelException('${e.programLabel} has no check-in tools (only KS2-3 Basic and Plus do).');
    }
    if (!e.isActive) throw const ViewModelException('The learner is not active in ARAL.');
    final tool = await _checkins.toolFor(e.keyStage, e.track!, checkpoint);
    if (tool == null) {
      throw ViewModelException('No ${e.programLabel} check-in tool for session $checkpoint on this device. Download the latest data (pull-cloud).');
    }
    final date = _checkDate(on, e);
    return _write(() => _checkins.insertCheckin(AralCheckin(
          enrollmentId: e.id!,
          toolId: tool.id,
          takenOn: date,
          notes: _blankToNull(notes),
          createdBy: _auth.currentUser?.id,
        )));
  }

  /// Changes the date and/or notes ([notes] '' clears them).
  Future<AralCheckin> editCheckin(int checkinId, {DateTime? on, String? notes}) async {
    _requireSignIn();
    _log('editCheckin($checkinId)');
    final (c, e) = await _requireCheckin(checkinId);
    return _write(() => _checkins.updateCheckin(c.copyWith(
          takenOn: on == null ? null : _checkDate(on, e),
          notes: notes == null ? null : () => _blankToNull(notes),
        )));
  }

  Future<void> deleteCheckin(int checkinId) async {
    _requireSignIn();
    _log('deleteCheckin($checkinId)');
    await _requireCheckin(checkinId);
    await _write(() => _checkins.deleteCheckin(checkinId));
  }

  /// Enters the learner's letters for consecutive choice items, starting at
  /// item [fromItemNo]; a null letter = left blank. Refused (nothing saved)
  /// when the run reaches an open item or the end of the tool.
  Future<List<AralCheckinAnswer>> answerChoices(int checkinId, int fromItemNo, List<String?> letters) async {
    _requireSignIn();
    _log('answerChoices($checkinId, $fromItemNo, $letters)');
    final (c, _) = await _requireCheckin(checkinId);
    final byNo = {for (final i in await _checkins.items(c.toolId)) i.itemNo: i};
    final targets = <(AralCheckinItem, String?)>[];
    for (var k = 0; k < letters.length; k++) {
      final item = byNo[fromItemNo + k];
      if (item == null) throw ViewModelException('The tool has no item ${fromItemNo + k}.');
      if (item.kind != AralCheckinItemKind.choice) {
        throw ViewModelException('Item ${item.displayNo} is an open item; mark it right or wrong instead.');
      }
      final l = letters[k]?.trim().toUpperCase();
      if (l != null && l.isNotEmpty && !RegExp(r'^[A-E]$').hasMatch(l)) {
        throw ViewModelException('Item ${item.displayNo}: "$l" is not a letter A-E.');
      }
      targets.add((item, l == null || l.isEmpty ? null : l));
    }
    final out = <AralCheckinAnswer>[];
    for (final (item, letter) in targets) {
      out.add(await _write(() => _checkins.saveAnswer(
          AralCheckinAnswer(checkinId: c.id!, itemId: item.id, response: letter, isCorrect: false))));
    }
    return out;
  }

  /// The tutor's mark for an open item, with what the learner wrote (optional).
  Future<AralCheckinAnswer> markOpen(int checkinId, int itemNo, bool correct, {String? response}) async {
    _requireSignIn();
    _log('markOpen($checkinId, $itemNo, $correct)');
    final (c, _) = await _requireCheckin(checkinId);
    final item = await _item(c, itemNo);
    if (item.kind != AralCheckinItemKind.open) {
      throw ViewModelException('Item ${item.displayNo} is multiple choice; enter the learner\'s letter instead.');
    }
    return _write(() => _checkins.saveAnswer(AralCheckinAnswer(
        checkinId: c.id!, itemId: item.id, response: _blankToNull(response), isCorrect: correct)));
  }

  /// Removes the answer to one item (back to "not answered").
  Future<void> clearAnswer(int checkinId, int itemNo) async {
    _requireSignIn();
    _log('clearAnswer($checkinId, $itemNo)');
    final (c, _) = await _requireCheckin(checkinId);
    final item = await _item(c, itemNo);
    await _write(() => _checkins.deleteAnswer(c.id!, item.id));
  }

  // ---- Cut-off ----

  /// The cut-off on this device: defaults <- region <- the school's override
  /// (the local mirror; pull-cloud refreshes it).
  Future<AralCheckinSettings> localSettings(int schoolId) async {
    _requireSignIn();
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralCheckinSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// The stored rows in the cloud (online) and the values that apply to
  /// [schoolId] (null = region only).
  Future<AralCheckinSettingLayers> settingLayers(int? schoolId) async {
    _requireSignIn();
    _log('settingLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.getRegion();
    final school = schoolId == null ? null : await cloud.getForSchool(schoolId);
    return AralCheckinSettingLayers(
        region, school, AralCheckinSettings.fromMap({...?region?.settings, ...?school?.settings}));
  }

  /// Sets the cut-off (1-100) of the region ([schoolId] null, superadmin) or a
  /// school (its admin/coordinator). Online; mirrored to this device.
  Future<AralSetting> setPassPct(int? schoolId, int passPct) async {
    _requireSignIn();
    _log('setPassPct($schoolId, $passPct)');
    final cloud = _settingsWriter(schoolId);
    if (passPct < 1 || passPct > 100) throw ViewModelException('The cut-off is a percentage 1-100, not $passPct.');
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(
        schoolId, {...?current?.settings, AralCheckinSettings.passPctKey: passPct}));
    await _mirror(() => _localSettings.upsertWithId(saved));
    return saved;
  }

  /// The foundational literacy program switch (SHARP) in the cloud: the stored
  /// region/school values (null = not set), the one that applies and the
  /// default (off).
  Future<({bool? region, bool? school, bool effective, bool defaults})> foundationalProgramLayers(
      int? schoolId) async {
    _requireSignIn();
    _log('foundationalProgramLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.getRegion();
    final school = schoolId == null ? null : await cloud.getForSchool(schoolId);
    bool? read(AralSetting? s) => s?.settings[AralProgramSettings.foundationalProgramKey] as bool?;
    return (
      region: read(region),
      school: read(school),
      effective: AralProgramSettings.fromMap({...?region?.settings, ...?school?.settings}).foundationalProgram,
      defaults: AralProgramSettings.defaults.foundationalProgram,
    );
  }

  /// Switches the foundational literacy program (SHARP) on or off for the
  /// region ([schoolId] null, superadmin) or a school (its admin/coordinator).
  /// Off = the current ARAL guidelines: learners at levels 0-1 go to KS1.
  /// Online; mirrored to this device. Learners already on the roster move at
  /// the next automatic update (applyResults).
  Future<AralSetting> setFoundationalProgram(int? schoolId, bool on) async {
    _requireSignIn();
    _log('setFoundationalProgram($schoolId, $on)');
    final cloud = _settingsWriter(schoolId);
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(
        schoolId, {...?current?.settings, AralProgramSettings.foundationalProgramKey: on}));
    await _mirror(() => _localSettings.upsertWithId(saved));
    return saved;
  }

  /// The extended KS1 program switch in the cloud (DepEd Memorandum 064:
  /// KS1 Developing/Transitioning learners join too): the stored region/school
  /// values (null = not set), the one that applies and the default (off).
  Future<({bool? region, bool? school, bool effective, bool defaults})> ks1ExtendedLayers(int? schoolId) async {
    _requireSignIn();
    _log('ks1ExtendedLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.getRegion();
    final school = schoolId == null ? null : await cloud.getForSchool(schoolId);
    bool? read(AralSetting? s) => s?.settings[AralProgramSettings.ks1ExtendedKey] as bool?;
    return (
      region: read(region),
      school: read(school),
      effective: AralProgramSettings.fromMap({...?region?.settings, ...?school?.settings}).ks1Extended,
      defaults: AralProgramSettings.defaults.ks1Extended,
    );
  }

  /// Switches the extended KS1 program on or off for the region ([schoolId]
  /// null, superadmin) or a school (its admin/coordinator). Off (the default)
  /// = the memo: only Low/High Emerging learners join, and Developing or
  /// Transitioning ARAL learners leave with classroom support at the next
  /// automatic update. Online; mirrored to this device.
  Future<AralSetting> setKs1Extended(int? schoolId, bool on) async {
    _requireSignIn();
    _log('setKs1Extended($schoolId, $on)');
    final cloud = _settingsWriter(schoolId);
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(
        schoolId, {...?current?.settings, AralProgramSettings.ks1ExtendedKey: on}));
    await _mirror(() => _localSettings.upsertWithId(saved));
    return saved;
  }

  /// The session settings on this device (idle_session_days): defaults <-
  /// region <- the school's override (the local mirror).
  Future<AralSessionSettings> localSessionSettings(int schoolId) async {
    _requireSignIn();
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralSessionSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// The "no session lately" reminder's day count in the cloud: the stored
  /// region/school values (null = not set), the one that applies and the
  /// default.
  Future<({int? region, int? school, int effective, int defaults})> idleSessionDaysLayers(int? schoolId) async {
    _requireSignIn();
    _log('idleSessionDaysLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.getRegion();
    final school = schoolId == null ? null : await cloud.getForSchool(schoolId);
    int? read(AralSetting? s) => (s?.settings[AralSessionSettings.idleSessionDaysKey] as num?)?.toInt();
    return (
      region: read(region),
      school: read(school),
      effective: AralSessionSettings.fromMap({...?region?.settings, ...?school?.settings}).idleSessionDays,
      defaults: AralSessionSettings.defaults.idleSessionDays,
    );
  }

  /// Sets after how many days without a session a tutor with active ARAL
  /// learners is reminded (1-60), for the region ([schoolId] null,
  /// superadmin) or a school (its admin/coordinator). Online; mirrored.
  Future<AralSetting> setIdleSessionDays(int? schoolId, int days) async {
    _requireSignIn();
    _log('setIdleSessionDays($schoolId, $days)');
    final cloud = _settingsWriter(schoolId);
    if (days < AralSessionSettings.minIdleSessionDays || days > AralSessionSettings.maxIdleSessionDays) {
      throw ViewModelException('The idle session days are a whole number '
          '${AralSessionSettings.minIdleSessionDays}-${AralSessionSettings.maxIdleSessionDays}, not $days.');
    }
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(
        schoolId, {...?current?.settings, AralSessionSettings.idleSessionDaysKey: days}));
    await _mirror(() => _localSettings.upsertWithId(saved));
    return saved;
  }

  /// Removes a school's override (all its ARAL settings: the check-in cut-off,
  /// the foundational program switch and the idle session days) so the region
  /// values apply again.
  Future<void> resetSchoolSettings(int schoolId) async {
    _requireSignIn();
    _log('resetSchoolSettings($schoolId)');
    final cloud = _settingsWriter(schoolId);
    if (await cloud.getForSchool(schoolId) == null) {
      throw ViewModelException('School $schoolId has no ARAL settings override.');
    }
    await _cloudWrite(() => cloud.deleteForSchool(schoolId));
    await _mirror(() => _localSettings.removeMirroredForSchool(schoolId));
  }

  // ---- helpers ----

  User _me() {
    final u = _auth.currentUser;
    if (u == null) throw const ViewModelException(notSignedInMessage);
    return u;
  }

  /// The tutor of the learner's ARAL class, or an admin/coordinator of the
  /// learner's school (any school for superadmin). Reading and writing alike.
  Future<AralEnrollment> _require(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (await _roster.classTutorId(e.id!) != me.id) {
        throw const ViewModelException('Forbidden: not your ARAL learner.');
      }
    } else if (me.role == UserRole.admin || me.role == UserRole.coordinator) {
      if (me.schoolId != null && me.schoolId != e.schoolId) {
        throw const ViewModelException('Forbidden: that learner is in another school.');
      }
    } else {
      throw const ViewModelException('Forbidden.');
    }
    return e;
  }

  Future<(AralCheckin, AralEnrollment)> _requireCheckin(int checkinId) async {
    final c = await _checkins.findCheckin(checkinId);
    if (c == null) throw ViewModelException('No check-in with id $checkinId.');
    return (c, await _require(c.enrollmentId));
  }

  Future<AralCheckinItem> _item(AralCheckin c, int itemNo) async {
    final item = (await _checkins.items(c.toolId)).where((i) => i.itemNo == itemNo).firstOrNull;
    if (item == null) throw ViewModelException('The tool has no item $itemNo.');
    return item;
  }

  /// Today or earlier, and not before the learner entered ARAL.
  String _checkDate(DateTime? on, AralEnrollment e) {
    final date = _date(on ?? DateTime.now());
    if (date.compareTo(_date(DateTime.now())) > 0) throw ViewModelException('The date $date is in the future.');
    if (date.compareTo(e.enteredOn) < 0) {
      throw ViewModelException('The date $date is before the learner entered ARAL (${e.enteredOn}).');
    }
    return date;
  }

  AralSettingRepository _cloud() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _cloudSettingsFor(_auth.client!);
  }

  /// [schoolId] null = region-wide. Also clears the previous mirror warning.
  AralSettingRepository _settingsWriter(int? schoolId) {
    final cloud = _cloud();
    final me = _me();
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    final superadmin = me.role == UserRole.admin && me.schoolId == null;
    if (!superadmin) {
      if (schoolId == null) {
        throw const ViewModelException('Forbidden: only the superadmin sets the region-wide ARAL settings.');
      }
      if (me.schoolId != schoolId) {
        throw const ViewModelException("Forbidden: you can only change your own school's ARAL settings.");
      }
    }
    lastMirrorWarning = null;
    return cloud;
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString().toLowerCase();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal.toLowerCase())) throw ViewModelException('$refusal.');
      }
      rethrow;
    }
  }

  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == '23514') throw const ViewModelException('The database refused the value (cut-off must be 1-100).');
      rethrow;
    }
  }

  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      // The detail goes to the log only: raw database text is no message for a screen (F20).
      lastMirrorWarning = 'ARAL settings saved online, but the copy on this device was not updated. Download the latest data (pull-cloud).';
      _log('WARNING: $lastMirrorWarning ($e)');
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
