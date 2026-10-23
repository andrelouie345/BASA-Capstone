// lib/viewmodels/aral_irip_viewmodel.dart
//
// ARAL-Reading Individual Reading Intervention Plan (piece A3b). Offline-first:
// reads and writes the local copy, like the roster and the session log.
//
// Owner decisions (2026-10-16):
//  * IRIPs exist for KS2-3 Basic, KS2 Plus and KS3 Plus; KS1 and Foundational
//    learners have none (for now).
//  * Basic runs a Filipino and an English strand in parallel; Plus one strand.
//  * Week 1 is pre-assigned (the list's first target). After a week is rated
//    BASA suggests the next target (aral_irip_rules.dart); the tutor may pick
//    any target of the list instead.
//  * A cycle is 8 weeks. When every strand's week 8 is rated (or the learner's
//    program changed) a new cycle starts, continuing from the target the
//    learner reached (from the list's start after a program change).
//  * The learner's ARAL tutor and the school's admins/coordinators write the
//    IRIP; other tutors can't see it here.
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_irip.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_irip_repository.dart';
import '../core/services/aral_irip_rules.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

/// One strand of the current cycle: its latest week and what comes next.
class AralIripStrandState {
  final AralIripStrand strand;
  final AralIripWeek? latest;          // null before the cycle's week 1
  final AralIripTarget? latestTarget;
  /// The suggested target of the next week; null when the latest week isn't
  /// rated yet, the cycle's week 8 is done, or the list is done (see
  /// [listDone]).
  final AralIripTarget? suggestion;
  /// The latest target (the list's last) was observed: the tutor picks a
  /// target to review.
  final bool listDone;

  const AralIripStrandState(this.strand, this.latest, this.latestTarget, this.suggestion, {this.listDone = false});

  bool get awaitingRating => latest != null && !latest!.isRated;
  bool get cycleDone => latest != null && latest!.weekNo >= aralIripWeeks && latest!.isRated;
}

/// A learner's IRIP: the program, every week, and the current cycle's state.
class AralIripPlan {
  final AralEnrollment enrollment;
  final AralIripProgram? program;          // null: no IRIP for this placement
  final List<AralIripTarget> targets;      // the program's active list
  final Map<int, AralIripTarget> targetById; // every target the weeks use
  final List<AralIripWeek> weeks;
  final int currentCycle;                  // 0 = not started
  final AralIripProgram? cycleProgram;     // the current cycle's list
  final List<AralIripStrandState> strands; // current cycle

  const AralIripPlan({
    required this.enrollment,
    required this.program,
    required this.targets,
    required this.targetById,
    required this.weeks,
    required this.currentCycle,
    required this.cycleProgram,
    required this.strands,
  });

  bool get hasIrip => program != null;
  bool get started => currentCycle > 0;

  /// The learner's program changed since the current cycle began.
  bool get programChanged => started && cycleProgram != program;

  bool get cycleDone => started && strands.every((s) => s.cycleDone);

  /// A new cycle may start: none yet, the current one is done, or the
  /// program changed.
  bool get canStartCycle => hasIrip && (!started || cycleDone || programChanged);
}

class AralIripViewModel {
  static const _dbRefusals = [
    'The learner is not active in ARAL',
    "That reading target is not in the learner's IRIP list",
    'An IRIP week needs the previous week of its cycle',
    'A rated IRIP week keeps its target',
    'An IRIP week keeps its learner, cycle, week and strand; only the target, status and notes change',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralIripRepository _irip;
  final AralEnrollmentRepository _roster;

  AralIripViewModel({
    required AuthViewModel auth,
    required AralIripRepository irip,
    required AralEnrollmentRepository roster,
    Logger? logger,
  })  : _auth = auth,
        _irip = irip,
        _roster = roster,
        _log = ScopedLogger(logger, 'AralIripViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Reading ----

  Future<List<AralIripTarget>> targets(AralIripProgram program) async {
    _requireSignIn();
    return _irip.targets(program);
  }

  /// The learner's IRIP ([enrollmentId] = ARAL enrollment id).
  Future<AralIripPlan> plan(int enrollmentId) async {
    _requireSignIn();
    _log('plan($enrollmentId)');
    return _plan(await _require(enrollmentId));
  }

  Future<AralIripPlan> _plan(AralEnrollment e) async {
    final program = AralIripProgram.of(e.keyStage, e.track);
    final list = program == null ? const <AralIripTarget>[] : await _irip.targets(program);
    final weeks = await _irip.weeks(e.id!);
    final byId = {for (final t in list) t.id: t};
    for (final w in weeks) {
      if (!byId.containsKey(w.targetId)) {
        final t = await _irip.findTarget(w.targetId);
        if (t != null) byId[t.id] = t;
      }
    }
    final cycle = weeks.isEmpty ? 0 : weeks.map((w) => w.cycleNo).reduce((a, b) => a > b ? a : b);
    final cycleWeeks = weeks.where((w) => w.cycleNo == cycle).toList();
    final cycleProgram = cycleWeeks.isEmpty ? null : byId[cycleWeeks.first.targetId]?.program;

    final strands = <AralIripStrandState>[];
    for (final strand in (cycleProgram ?? program)?.strands ?? const <AralIripStrand>[]) {
      final mine = cycleWeeks.where((w) => w.strand == strand).toList()..sort((a, b) => a.weekNo.compareTo(b.weekNo));
      final latest = mine.lastOrNull;
      final latestTarget = latest == null ? null : byId[latest.targetId];
      AralIripTarget? suggestion;
      var listDone = false;
      if (latest != null && latest.isRated && latest.weekNo < aralIripWeeks && latestTarget != null) {
        suggestion = aralIripSuggest(list.where((t) => t.strand == strand).toList(), latestTarget, latest.status!);
        listDone = suggestion == null;
      }
      strands.add(AralIripStrandState(strand, latest, latestTarget, suggestion, listDone: listDone));
    }
    return AralIripPlan(
      enrollment: e,
      program: program,
      targets: list,
      targetById: byId,
      weeks: weeks,
      currentCycle: cycle,
      cycleProgram: cycleProgram,
      strands: strands,
    );
  }

  // ---- Writing ----

  /// Starts the IRIP (cycle 1) or its next cycle: week 1 of every strand.
  /// Cycle 1 (and a cycle after a program change) starts at the list's first
  /// target; a later cycle continues from where each strand reached.
  Future<List<AralIripWeek>> startCycle(int enrollmentId) async {
    _requireSignIn();
    _log('startCycle($enrollmentId)');
    final e = await _requireWritable(enrollmentId);
    final p = await _plan(e);
    if (!p.hasIrip) {
      throw ViewModelException('${e.programLabel} has no IRIP (only KS2-3 Basic, KS2 Plus and KS3 Plus do).');
    }
    if (!e.isActive) throw const ViewModelException('The learner is not active in ARAL.');
    if (!p.canStartCycle) {
      throw ViewModelException('Cycle ${p.currentCycle} is still running; rate week $aralIripWeeks of every strand '
          'before starting the next cycle.');
    }
    final continuing = p.started && !p.programChanged;
    final out = <AralIripWeek>[];
    for (final strand in p.program!.strands) {
      final list = p.targets.where((t) => t.strand == strand).toList();
      AralIripTarget? target;
      if (continuing) {
        final s = p.strands.firstWhere((s) => s.strand == strand);
        // after week 8: the suggestion from its rating; a finished list restarts
        target = s.latestTarget == null ? null : aralIripSuggest(list, s.latestTarget!, s.latest!.status!);
      }
      target ??= aralIripFirst(list);
      if (target == null) throw ViewModelException('The ${p.program!.label} target list is empty; pull the content first.');
      out.add(await _write(() => _irip.insertWeek(AralIripWeek(
            enrollmentId: e.id!,
            cycleNo: p.currentCycle + 1,
            weekNo: 1,
            strand: strand,
            targetId: target!.id,
            createdBy: _auth.currentUser?.id,
          ))));
    }
    _log('started cycle ${p.currentCycle + 1} for enrollment ${e.id}');
    return out;
  }

  /// Rates a week (status, date, optional notes). Rating again replaces it.
  Future<AralIripWeek> rate(int weekId, AralIripStatus status, {DateTime? on, String? notes}) async {
    _requireSignIn();
    _log('rate($weekId, ${status.value})');
    final w = await _requireWeek(weekId);
    final date = _date(on ?? DateTime.now());
    if (date.compareTo(_date(DateTime.now())) > 0) throw ViewModelException('The date $date is in the future.');
    return _write(() => _irip.updateWeek(w.copyWith(
          status: () => status,
          ratedOn: () => date,
          notes: notes == null ? null : () => _blankToNull(notes),
        )));
  }

  /// Removes a week's rating (e.g. rated by mistake); only while the strand
  /// has no later week.
  Future<AralIripWeek> clearRating(int weekId) async {
    _requireSignIn();
    _log('clearRating($weekId)');
    final w = await _requireWeek(weekId);
    await _requireLast(w, 'clear its rating');
    return _write(() => _irip.updateWeek(w.copyWith(status: () => null, ratedOn: () => null)));
  }

  Future<AralIripWeek> setNotes(int weekId, String? notes) async {
    _requireSignIn();
    _log('setNotes($weekId)');
    final w = await _requireWeek(weekId);
    return _write(() => _irip.updateWeek(w.copyWith(notes: () => _blankToNull(notes))));
  }

  /// Picks another target for a week that isn't rated yet.
  Future<AralIripWeek> changeTarget(int weekId, int targetId) async {
    _requireSignIn();
    _log('changeTarget($weekId, $targetId)');
    final w = await _requireWeek(weekId);
    if (w.isRated) throw const ViewModelException('A rated IRIP week keeps its target.');
    await _checkTarget(w.enrollmentId, w.strand, targetId);
    return _write(() => _irip.updateWeek(w.copyWith(targetId: targetId)));
  }

  /// Adds the next week of the current cycle for [strand] (every strand that
  /// is ready, when null) with the suggested target, or [targetId].
  Future<List<AralIripWeek>> nextWeek(int enrollmentId, {AralIripStrand? strand, int? targetId}) async {
    _requireSignIn();
    _log('nextWeek($enrollmentId, strand: ${strand?.name}, target: $targetId)');
    final e = await _requireWritable(enrollmentId);
    if (!e.isActive) throw const ViewModelException('The learner is not active in ARAL.');
    final p = await _plan(e);
    if (!p.started) throw const ViewModelException('The IRIP has not started; start the cycle first.');
    if (p.programChanged) {
      throw ViewModelException('The learner moved to ${e.programLabel}; start a new cycle for the new target list.');
    }
    final states = strand == null ? p.strands : p.strands.where((s) => s.strand == strand).toList();
    if (states.isEmpty) throw ViewModelException('${p.cycleProgram!.label} has no ${strand!.name} strand.');
    if (targetId != null && states.length > 1) {
      throw const ViewModelException('Name the strand (filipino or english) when picking a target.');
    }
    final out = <AralIripWeek>[];
    final problems = <String>[];
    for (final s in states) {
      final name = s.strand == AralIripStrand.main ? '' : '${s.strand.label}: ';
      if (s.awaitingRating) {
        problems.add('${name}rate week ${s.latest!.weekNo} first');
        continue;
      }
      if (s.cycleDone) {
        problems.add('${name}week $aralIripWeeks is done; start a new cycle');
        continue;
      }
      final pick = targetId ?? s.suggestion?.id;
      if (pick == null) {
        problems.add('${name}every target of the list is observed; pick one to review (target=<id>)');
        continue;
      }
      if (targetId != null) await _checkTarget(e.id!, s.strand, targetId);
      out.add(await _write(() => _irip.insertWeek(AralIripWeek(
            enrollmentId: e.id!,
            cycleNo: p.currentCycle,
            weekNo: s.latest!.weekNo + 1,
            strand: s.strand,
            targetId: pick,
            createdBy: _auth.currentUser?.id,
          ))));
    }
    if (out.isEmpty) throw ViewModelException('No week added: ${problems.join('; ')}.');
    return out;
  }

  /// Deletes a week added by mistake: only the last week of its strand.
  Future<void> deleteWeek(int weekId) async {
    _requireSignIn();
    _log('deleteWeek($weekId)');
    final w = await _requireWeek(weekId);
    await _requireLast(w, 'be deleted');
    await _write(() => _irip.deleteWeek(weekId));
  }

  // ---- helpers ----

  User _me() {
    final u = _auth.currentUser;
    if (u == null) throw const ViewModelException(notSignedInMessage);
    return u;
  }

  /// Readable and writable alike here: the learner's ARAL tutor, or an
  /// admin/coordinator of the learner's school (any school for superadmin).
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

  Future<AralEnrollment> _requireWritable(int enrollmentId) => _require(enrollmentId);

  Future<AralIripWeek> _requireWeek(int weekId) async {
    final w = await _irip.findWeek(weekId);
    if (w == null) throw ViewModelException('No IRIP week with id $weekId.');
    await _requireWritable(w.enrollmentId);
    return w;
  }

  Future<void> _requireLast(AralIripWeek w, String what) async {
    final later = (await _irip.weeks(w.enrollmentId)).any((x) =>
        x.strand == w.strand && (x.cycleNo > w.cycleNo || (x.cycleNo == w.cycleNo && x.weekNo > w.weekNo)));
    if (later) throw ViewModelException('Only the latest week of a strand can $what.');
  }

  Future<void> _checkTarget(int enrollmentId, AralIripStrand strand, int targetId) async {
    final e = (await _roster.findById(enrollmentId))!;
    final t = await _irip.findTarget(targetId);
    final program = AralIripProgram.of(e.keyStage, e.track);
    if (t == null || !t.isActive || t.program != program || t.strand != strand) {
      throw ViewModelException('Target $targetId is not in this learner\'s ${program?.label ?? ''} '
          '${strand == AralIripStrand.main ? '' : '${strand.label} '}list.');
    }
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

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
