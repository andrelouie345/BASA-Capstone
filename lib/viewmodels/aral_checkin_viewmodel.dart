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
import '../core/services/csv.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
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

  // ---- Reading ----

  Future<List<AralCheckinTool>> tools() => _checkins.tools();

  Future<List<AralCheckinItem>> items(int toolId) => _checkins.items(toolId);

  /// The learner's check-ins ([enrollmentId] = ARAL enrollment id), scored
  /// with today's cut-off for the learner's school.
  Future<AralLearnerCheckins> learnerCheckins(int enrollmentId) async {
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
    _log('result($checkinId)');
    final (c, e) = await _requireCheckin(checkinId);
    return _result(c, (await localSettings(e.schoolId)).passPct);
  }

  Future<AralCheckinResult> _result(AralCheckin c, int passPct) async {
    final tool = await _checkins.findTool(c.toolId);
    if (tool == null) throw ViewModelException('Check-in tool ${c.toolId} is not on this device; run pull-cloud.');
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
        final latest = <int, AralCheckinResult>{};
        for (final c in await _checkins.checkins(e.id!)) {
          final r = await _result(c, passPct);
          final prev = latest[r.tool.checkpoint];
          final newer = prev == null ||
              c.takenOn.compareTo(prev.checkin.takenOn) > 0 ||
              (c.takenOn == prev.checkin.takenOn && c.attemptNo > prev.checkin.attemptNo);
          if (newer) latest[r.tool.checkpoint] = r;
        }
        learners.add(AralCheckinReportLearner(e, names[e.studentId] ?? 'student ${e.studentId}', latest[16], latest[32]));
      }
      learners.sort((a, b) => a.name.compareTo(b.name));
      out.add(AralCheckinReportSection(s, learners));
    }
    return AralCheckinReport(schoolId, schoolYear, passPct, out);
  }

  /// [checkinReport] as CSV: one line per learner.
  Future<String> checkinReportCsv({required int schoolId, required String schoolYear, int? sectionId}) async {
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
      throw ViewModelException('No ${e.programLabel} check-in tool for session $checkpoint on this device; run pull-cloud.');
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
    _log('editCheckin($checkinId)');
    final (c, e) = await _requireCheckin(checkinId);
    return _write(() => _checkins.updateCheckin(c.copyWith(
          takenOn: on == null ? null : _checkDate(on, e),
          notes: notes == null ? null : () => _blankToNull(notes),
        )));
  }

  Future<void> deleteCheckin(int checkinId) async {
    _log('deleteCheckin($checkinId)');
    await _requireCheckin(checkinId);
    await _checkins.deleteCheckin(checkinId);
  }

  /// Enters the learner's letters for consecutive choice items, starting at
  /// item [fromItemNo]; a null letter = left blank. Refused (nothing saved)
  /// when the run reaches an open item or the end of the tool.
  Future<List<AralCheckinAnswer>> answerChoices(int checkinId, int fromItemNo, List<String?> letters) async {
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
    _log('clearAnswer($checkinId, $itemNo)');
    final (c, _) = await _requireCheckin(checkinId);
    final item = await _item(c, itemNo);
    await _checkins.deleteAnswer(c.id!, item.id);
  }

  // ---- Cut-off ----

  /// The cut-off on this device: defaults <- region <- the school's override
  /// (the local mirror; pull-cloud refreshes it).
  Future<AralCheckinSettings> localSettings(int schoolId) async {
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralCheckinSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// The stored rows in the cloud (online) and the values that apply to
  /// [schoolId] (null = region only).
  Future<AralCheckinSettingLayers> settingLayers(int? schoolId) async {
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
    _log('setPassPct($schoolId, $passPct)');
    final cloud = _settingsWriter(schoolId);
    if (passPct < 1 || passPct > 100) throw ViewModelException('The cut-off is a percentage 1-100, not $passPct.');
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(
        schoolId, {...?current?.settings, AralCheckinSettings.passPctKey: passPct}));
    await _mirror(() => _localSettings.upsertWithId(saved));
    return saved;
  }

  /// Removes a school's override so the region value applies again.
  Future<void> resetSchoolSettings(int schoolId) async {
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
    if (u == null) throw const ViewModelException('Not signed in.');
    return u;
  }

  /// The learner's ARAL tutor, or an admin/coordinator of the learner's
  /// school (any school for superadmin). Reading and writing alike.
  Future<AralEnrollment> _require(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (e.tutorId != me.id) throw const ViewModelException('Forbidden: not your ARAL learner.');
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
    final sessionError = _auth.requireActiveSession();
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
        throw const ViewModelException('Forbidden: only the superadmin sets the region-wide cut-off.');
      }
      if (me.schoolId != schoolId) {
        throw const ViewModelException('Forbidden: you can only set the cut-off of your own school.');
      }
    }
    lastMirrorWarning = null;
    return cloud;
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
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
      lastMirrorWarning = 'ARAL settings saved online, but the local copy was not updated ($e). Run pull-cloud.';
      _log('WARNING: $lastMirrorWarning');
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
