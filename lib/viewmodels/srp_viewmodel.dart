// lib/viewmodels/srp_viewmodel.dart
//
// Summer Remediation Program (SRP). Part 1: per Grade 4-10 section, the
// learners not grade level ready by the end of the year, ranked weakest first
// (srp_rules.dart), the weakest [perSection] recommended; read-only, from this
// device's copy. Part 2: the SRP classes (sheet "SRP Masterlist"): the
// recommended learners grouped by grade and the grade they were assessed at,
// in classes of at most 15; the coordinator sets tutor, room and schedule and
// moves learners. Classes are written online and mirrored to this device.
//
// Reading coordinator's workbook (sheets 01-40, GZ/HA; owner 2026-10-19):
//  * not grade level ready = EOSY profile Frustration or Non-Reader; a learner
//    without an EOSY reading keeps the latest round's result (it carries);
//  * comprehension = the EOSY reading's own score when there is one, else the
//    carried one (her sheet compared her EOSY score in percent with the
//    carried one as a fraction, so learners without an EOSY reading always
//    ranked weakest; BASA compares both as fractions);
//  * learners not assessed at all are in, ranked weakest, flagged (as ARAL).
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/srp_class.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/srp_class_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/auth_messages.dart';
import '../core/services/csv.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart' show philIriNotAssessedResult;
import '../core/services/phil_iri_rules.dart' show PhilIriLevel;
import '../core/services/srp_rules.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart' show NlaReportViewModel, progressPercent;
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

class SrpCandidate {
  final Student student;
  final int rank;                  // 1 = weakest; equal results share a rank
  final bool recommended;          // rank within the section's cap
  final bool notAssessed;          // no Phil-IRI result at all this year
  final PhilIriRound? basisRound;  // the round the result comes from (null if not assessed)
  final PhilIriLevel profile;      // Frustration or Non-Reader
  final int adjustedLevel;         // 0 for a Non-Reader
  final int? levelsDown;
  final SrpRankKey key;

  const SrpCandidate({
    required this.student,
    required this.rank,
    required this.recommended,
    required this.notAssessed,
    required this.basisRound,
    required this.profile,
    required this.adjustedLevel,
    required this.levelsDown,
    required this.key,
  });

  String get name => '${student.lastName}, ${student.firstName}';
}

class SrpSection {
  final Section section;
  final int grade;
  final int enrolled;
  final List<SrpCandidate> candidates; // weakest first, then by name

  const SrpSection(this.section, this.grade, this.enrolled, this.candidates);

  int get recommendedCount => candidates.where((c) => c.recommended).length;
}

class SrpList {
  final int schoolId;
  final String schoolYear;
  final String asOf;
  final int perSection;
  final List<SrpSection> sections; // by grade, then name

  const SrpList(this.schoolId, this.schoolYear, this.asOf, this.perSection, this.sections);
}

/// The list as CSV: one row per candidate ([recommendedOnly]: only those
/// within the cap).
String srpListCsv(SrpList list, {bool recommendedOnly = false}) {
  String pct(double v) => progressPercent(v);
  return csvTable([
    ['Grade', 'Section', 'Rank', 'Recommended', 'LRN', 'Learner', 'Sex', 'Adjusted grade level', 'Levels down',
      'Profile', 'Comprehension %', 'Word recognition %', 'Speed (wpm)', 'Result from', 'Not assessed'],
    for (final s in list.sections)
      for (final c in s.candidates)
        if (!recommendedOnly || c.recommended)
          [
            s.grade, s.section.sectionName, c.rank, c.recommended ? 'yes' : '', c.student.lrn, c.name,
            c.student.sex ?? '', c.adjustedLevel, c.levelsDown ?? '', c.profile.label,
            c.notAssessed ? '' : pct(c.key.comprehension), c.notAssessed ? '' : pct(c.key.wordRecognition),
            c.notAssessed ? '' : c.key.speed.toStringAsFixed(0), c.basisRound?.label ?? '',
            c.notAssessed ? 'yes' : '',
          ],
  ]);
}

// ---- classes (part 2) ----

/// A learner in an SRP class, with their section this school year (null when
/// the learner is not on this device's copy).
class SrpClassLearner {
  final SrpClassMember member;
  final Student? student;
  final Section? section;

  const SrpClassLearner(this.member, this.student, this.section);

  String get name => student == null ? 'student ${member.studentId}' : '${student!.lastName}, ${student!.firstName}';
}

class SrpClassView {
  final SrpClass srpClass;
  final User? tutor; // null: none set, or not on this device
  final List<SrpClassLearner> learners; // by name

  const SrpClassView(this.srpClass, this.tutor, this.learners);
}

/// The SRP masterlist: [schoolId]'s classes for the year, by assessed grade
/// then name.
String srpClassesCsv(List<SrpClassView> classes) => csvTable([
      ['Class', 'Assessed grade', 'Room', 'Schedule', 'Tutor', 'No.', 'LRN', 'Learner', 'Sex', 'Grade', 'Section'],
      for (final c in classes)
        for (final (i, l) in c.learners.indexed)
          [
            c.srpClass.className, c.srpClass.assessedLabel, c.srpClass.room ?? '', c.srpClass.schedule ?? '',
            c.tutor?.fullName ?? '', i + 1, l.student?.lrn ?? '', l.name, l.student?.sex ?? '',
            l.section?.gradeLevel ?? '', l.section?.sectionName ?? '',
          ],
    ]);

class SrpViewModel {
  final ScopedLogger _log;
  final NlaReportViewModel _reports;
  final StudentRepository _students;
  final PhilIriViewModel _philIri;
  final AuthViewModel _auth;
  final SrpClassRepository _local;
  final SrpClassRepository Function(SupabaseClient client) _cloudFor;
  final UserRepository _users;
  final SectionRepository _sections;

  /// Set when the last class change reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  SrpViewModel({
    required NlaReportViewModel reports,
    required StudentRepository students,
    required PhilIriViewModel philIri,
    required AuthViewModel auth,
    required SrpClassRepository local,
    required SrpClassRepository Function(SupabaseClient client) cloud,
    required UserRepository users,
    required SectionRepository sections,
    Logger? logger,
  })  : _reports = reports,
        _students = students,
        _philIri = philIri,
        _auth = auth,
        _local = local,
        _cloudFor = cloud,
        _users = users,
        _sections = sections,
        _log = ScopedLogger(logger, 'SrpViewModel');

  /// The SRP candidates of every Grade 4-10 section of the school
  /// ([sectionIds] narrows it) as of [asOf] (default today), the weakest
  /// [perSection] (default 15) recommended: admin/coordinator of the school,
  /// or the superadmin.
  Future<SrpList> candidates({
    required int schoolId,
    required String schoolYear,
    Set<int>? sectionIds,
    int perSection = srpDefaultPerSection,
    DateTime? asOf,
  }) async {
    _log('candidates(school: $schoolId, year: $schoolYear, sections: $sectionIds, perSection: $perSection)');
    if (perSection < 1) throw ViewModelException('Learners per section is at least 1 (got $perSection).');
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = await _reports.reportSections(schoolId, schoolYear, sectionIds, 'the SRP list');
    final date = _date(asOf ?? DateTime.now());
    final out = <SrpSection>[];
    for (final s in sections) {
      final grade = int.parse(s.gradeLevel);
      final learners = await _students.getBySection(s.id!);
      final drafts = <_Draft>[];
      for (final st in learners) {
        final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: schoolYear, asOf: date);
        if (res.notAssessed) {
          final assumed = philIriNotAssessedResult(PhilIriRound.eosy, grade);
          drafts.add(_Draft(st, true, null, assumed.profile!, assumed.adjustedLevel!, assumed.levelsDown,
              const SrpRankKey(0, 0, 0)));
          continue;
        }
        final eosy = res.round(PhilIriRound.eosy); // carries the latest round when EOSY was not given
        final profile = eosy.profile;
        if (profile != PhilIriLevel.frustration && profile != PhilIriLevel.nonReader) continue;
        final own = res.counted.contains(PhilIriRound.eosy) ? eosy.actual?.comprehensionScore : null;
        drafts.add(_Draft(
          st,
          false,
          res.latest(PhilIriRound.values)?.round,
          profile!,
          eosy.adjustedLevel ?? 0,
          eosy.levelsDown,
          SrpRankKey(own ?? eosy.comprehensionScore ?? 0, eosy.wordReadingScore ?? 0, eosy.wordsPerMinute ?? 0),
        ));
      }
      final ranks = srpRanks([for (final d in drafts) d.key]);
      final list = [
        for (final (i, d) in drafts.indexed)
          SrpCandidate(
            student: d.student,
            rank: ranks[i],
            recommended: ranks[i] <= perSection,
            notAssessed: d.notAssessed,
            basisRound: d.basisRound,
            profile: d.profile,
            adjustedLevel: d.adjustedLevel,
            levelsDown: d.levelsDown,
            key: d.key,
          ),
      ]..sort((a, b) {
          final r = a.rank.compareTo(b.rank);
          if (r != 0) return r;
          final l = a.student.lastName.toUpperCase().compareTo(b.student.lastName.toUpperCase());
          return l != 0 ? l : a.student.firstName.toUpperCase().compareTo(b.student.firstName.toUpperCase());
        });
      out.add(SrpSection(s, grade, learners.length, list));
    }
    return SrpList(schoolId, schoolYear, date, perSection, out);
  }

  // ---- classes (part 2) ----

  /// [schoolId]'s SRP classes for the year from this device's copy: an
  /// admin/coordinator of the school (any school for the superadmin), or a
  /// tutor of the school (only the classes they tutor).
  Future<List<SrpClassView>> classes({required int schoolId, required String schoolYear}) async {
    _log('classes(school: $schoolId, year: $schoolYear)');
    final me = _me();
    schoolYear = normalizeSchoolYear(schoolYear);
    final manager = _manages(me, schoolId);
    if (!manager && !(me.role == UserRole.tutor && me.schoolId == schoolId)) {
      throw const ViewModelException("Forbidden: that school's SRP classes are not yours to see.");
    }
    var list = await _local.classesFor(schoolId, schoolYear);
    if (!manager) list = list.where((c) => c.tutorId == me.id).toList();
    final members = await _local.membersFor(schoolId, schoolYear);
    final learners = await _schoolLearners(schoolId, schoolYear);
    // An SRP tutor's device has the learners of their classes (cloud policy
    // students_select_srp_tutor) but not their enrollments or sections.
    final byId = <int, Student>{};
    if (members.any((m) => !learners.containsKey(m.studentId))) {
      for (final st in await _students.getAll('id')) {
        byId[st.id!] = st;
      }
    }
    final views = <SrpClassView>[];
    for (final c in list) {
      final inClass = [
        for (final m in members.where((m) => m.classId == c.id))
          SrpClassLearner(m, learners[m.studentId]?.$1 ?? byId[m.studentId], learners[m.studentId]?.$2),
      ]..sort((a, b) => a.name.toUpperCase().compareTo(b.name.toUpperCase()));
      views.add(SrpClassView(c, c.tutorId == null ? null : await _users.getById(c.tutorId!), inClass));
    }
    return views;
  }

  /// Builds the school's SRP classes for the year from the recommended
  /// learners ([candidates] with [perSection]): grouped by their grade and the
  /// grade they were assessed at, split into classes of at most [classSize]
  /// (srpClassSizes), named 7-3A / 7A-SHARP (srpClassName), learners by name.
  /// Online. Refused while the school already has SRP classes that year
  /// (change them, or clear them first). If a write fails midway, the classes
  /// made so far are deleted again.
  Future<List<SrpClassView>> buildClasses({
    required int schoolId,
    required String schoolYear,
    int perSection = srpDefaultPerSection,
    int classSize = srpDefaultClassSize,
    DateTime? asOf,
  }) async {
    _log('buildClasses(school: $schoolId, year: $schoolYear, perSection: $perSection, classSize: $classSize)');
    if (classSize < 1) throw ViewModelException('A class holds at least 1 learner (got $classSize).');
    schoolYear = normalizeSchoolYear(schoolYear);
    final cloud = _writer(schoolId);
    final existing = await _cloudWrite(() => cloud.classesFor(schoolId, schoolYear));
    if (existing.isNotEmpty) {
      throw ViewModelException('School $schoolId already has ${existing.length} SRP class(es) for $schoolYear: '
          'change them, or delete them all first.');
    }
    final list = await candidates(schoolId: schoolId, schoolYear: schoolYear, perSection: perSection, asOf: asOf);
    final groups = <(int, int), List<SrpCandidate>>{};
    for (final s in list.sections) {
      for (final c in s.candidates.where((c) => c.recommended)) {
        groups.putIfAbsent((s.grade, c.adjustedLevel), () => []).add(c);
      }
    }
    final keys = groups.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final created = <SrpClass>[];
    try {
      for (final key in keys) {
        final group = groups[key]!..sort((a, b) => a.name.toUpperCase().compareTo(b.name.toUpperCase()));
        var at = 0;
        for (final (i, size) in srpClassSizes(group.length, classSize).indexed) {
          final cls = await _cloudWrite(() => cloud.insertClass(SrpClass(
              schoolId: schoolId,
              schoolYear: schoolYear,
              assessedGrade: key.$2,
              className: srpClassName(key.$1, key.$2, i))));
          created.add(cls);
          await _mirror(() => _local.upsertClassWithId(cls));
          for (final c in group.sublist(at, at + size)) {
            final m = await _cloudWrite(() => cloud.insertMember(cls.id!, c.student.id!, schoolYear));
            await _mirror(() => _local.upsertMemberWithId(m));
          }
          at += size;
        }
      }
    } catch (_) {
      for (final c in created) {
        try {
          await cloud.deleteClass(c.id!); // its learners go with it
        } catch (_) {}
        await _mirror(() => _local.removeMirroredClass(c.id!));
      }
      rethrow;
    }
    return classes(schoolId: schoolId, schoolYear: schoolYear);
  }

  /// Changes a class's name, room, schedule or tutor (online). The tutor is
  /// given by email: an active user with the tutor role of the class's school.
  Future<SrpClassView> updateClass(
    int classId, {
    String? className,
    String? room,
    String? schedule,
    String? tutorEmail,
    bool clearRoom = false,
    bool clearSchedule = false,
    bool clearTutor = false,
  }) async {
    _log('updateClass($classId)');
    final current = await _class(classId);
    final cloud = _writer(current.schoolId);
    if (className != null && className.trim().isEmpty) throw const ViewModelException('Give the class a name.');
    String? tutorId;
    if (tutorEmail != null) {
      final u = await _users.getByEmail(tutorEmail.trim());
      if (u == null) throw ViewModelException('No user $tutorEmail on this device (run pull-cloud).');
      if (u.role != UserRole.tutor || !u.isActive || u.schoolId != current.schoolId) {
        throw ViewModelException('${u.email} is not an active tutor of school ${current.schoolId}.');
      }
      tutorId = u.id;
    }
    final saved = await _cloudWrite(() => cloud.updateClass(current.copyWith(
          className: className?.trim(),
          room: _blankToNull(room),
          schedule: _blankToNull(schedule),
          tutorId: tutorId,
          clearRoom: clearRoom,
          clearSchedule: clearSchedule,
          clearTutor: clearTutor,
        )));
    await _mirror(() => _local.upsertClassWithId(saved));
    return _view(saved);
  }

  /// Puts a learner in a class (online): enrolled in a section of the class's
  /// school that year and not yet in an SRP class.
  Future<SrpClassView> addLearner(int classId, int studentId) async {
    _log('addLearner(class: $classId, student: $studentId)');
    final cls = await _class(classId);
    final cloud = _writer(cls.schoolId);
    final members = await _local.membersFor(cls.schoolId, cls.schoolYear);
    final already = members.where((m) => m.studentId == studentId).firstOrNull;
    if (already != null) {
      final other = await _local.findClass(already.classId);
      throw ViewModelException('Learner $studentId is already in SRP class ${other?.className ?? already.classId}; '
          'move them instead.');
    }
    if (!(await _schoolLearners(cls.schoolId, cls.schoolYear)).containsKey(studentId)) {
      throw ViewModelException('Learner $studentId is not enrolled in a section of school ${cls.schoolId} '
          'for ${cls.schoolYear}.');
    }
    final m = await _cloudWrite(() => cloud.insertMember(classId, studentId, cls.schoolYear));
    await _mirror(() => _local.upsertMemberWithId(m));
    return _view(cls);
  }

  /// Moves a learner from their SRP class to [toClassId] (same school and year).
  Future<SrpClassView> moveLearner(int studentId, int toClassId) async {
    _log('moveLearner(student: $studentId, to: $toClassId)');
    final to = await _class(toClassId);
    final cloud = _writer(to.schoolId);
    final member = (await _local.membersFor(to.schoolId, to.schoolYear))
        .where((m) => m.studentId == studentId)
        .firstOrNull;
    if (member == null) {
      throw ViewModelException('Learner $studentId is in no SRP class of school ${to.schoolId} for ${to.schoolYear}.');
    }
    if (member.classId == toClassId) throw ViewModelException('Learner $studentId is already in ${to.className}.');
    final moved = await _cloudWrite(() => cloud.moveMember(member.id!, toClassId));
    await _mirror(() => _local.upsertMemberWithId(moved));
    return _view(to);
  }

  /// Takes a learner out of their SRP class (online).
  Future<SrpClassView> removeLearner(int classId, int studentId) async {
    _log('removeLearner(class: $classId, student: $studentId)');
    final cls = await _class(classId);
    final cloud = _writer(cls.schoolId);
    final member = (await _local.membersFor(cls.schoolId, cls.schoolYear))
        .where((m) => m.classId == classId && m.studentId == studentId)
        .firstOrNull;
    if (member == null) throw ViewModelException('Learner $studentId is not in ${cls.className}.');
    await _cloudWrite(() => cloud.deleteMember(member.id!));
    await _mirror(() => _local.removeMirroredMember(member.id!));
    return _view(cls);
  }

  /// Deletes a class and takes its learners out (online).
  Future<void> deleteClass(int classId) async {
    _log('deleteClass($classId)');
    final cls = await _class(classId);
    final cloud = _writer(cls.schoolId);
    await _cloudWrite(() => cloud.deleteClass(classId));
    await _mirror(() => _local.removeMirroredClass(classId));
  }

  /// Deletes every SRP class of the school for the year (online), e.g. to
  /// build them again. Returns how many were deleted.
  Future<int> clearClasses({required int schoolId, required String schoolYear}) async {
    _log('clearClasses(school: $schoolId, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final cloud = _writer(schoolId);
    final list = await _cloudWrite(() => cloud.classesFor(schoolId, schoolYear));
    for (final c in list) {
      await _cloudWrite(() => cloud.deleteClass(c.id!));
      await _mirror(() => _local.removeMirroredClass(c.id!));
    }
    return list.length;
  }

  /// The id of the class [ref] names on this device: its id, or its exact
  /// name (any case) when only one class has it.
  Future<int> classIdFor(String ref) async {
    final id = int.tryParse(ref.trim());
    if (id != null) return id;
    final found = await _local.findClassesByName(ref);
    if (found.isEmpty) throw ViewModelException('No SRP class named "$ref" on this device.');
    if (found.length > 1) {
      throw ViewModelException('${found.length} SRP classes are named "$ref" (ids ${found.map((c) => c.id).join(', ')}); '
          'use the id.');
    }
    return found.single.id!;
  }

  // ---- helpers ----

  User _me() {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    return me;
  }

  static bool _manages(User me, int schoolId) =>
      (me.role == UserRole.admin && me.schoolId == null) ||
      ((me.role == UserRole.admin || me.role == UserRole.coordinator) && me.schoolId == schoolId);

  /// The cloud repository for a change to [schoolId]'s SRP classes: an online
  /// session of an admin/coordinator of the school, or the superadmin.
  SrpClassRepository _writer(int schoolId) {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    if (!_manages(_me(), schoolId)) {
      throw const ViewModelException("Forbidden: only an admin or coordinator of the school manages its SRP classes.");
    }
    lastMirrorWarning = null;
    return _cloudFor(_auth.client!);
  }

  Future<SrpClass> _class(int id) async {
    final c = await _local.findClass(id);
    if (c == null) throw ViewModelException('No SRP class with id $id on this device (run pull-cloud).');
    return c;
  }

  Future<SrpClassView> _view(SrpClass c) async =>
      (await classes(schoolId: c.schoolId, schoolYear: c.schoolYear)).firstWhere((v) => v.srpClass.id == c.id);

  /// Every learner on this device enrolled in a section of [schoolId] for the
  /// year, with that section.
  Future<Map<int, (Student, Section)>> _schoolLearners(int schoolId, String schoolYear) async {
    final out = <int, (Student, Section)>{};
    for (final s in await _sections.getAll()) {
      if (s.schoolId != schoolId || s.schoolYear != schoolYear) continue;
      for (final st in await _students.getBySection(s.id!)) {
        out[st.id!] = (st, s);
      }
    }
    return out;
  }

  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == '23505') {
        throw const ViewModelException(
            'Already there: a class with that name exists, or the learner is already in an SRP class this school year.');
      }
      if (e.code == 'P0001' || e.code == '23514') throw ViewModelException('The database refused it: ${e.message}.');
      rethrow;
    }
  }

  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = 'The SRP classes were changed online, but the local copy was not updated ($e). Run pull-cloud.';
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

class _Draft {
  final Student student;
  final bool notAssessed;
  final PhilIriRound? basisRound;
  final PhilIriLevel profile;
  final int adjustedLevel;
  final int? levelsDown;
  final SrpRankKey key;

  const _Draft(this.student, this.notAssessed, this.basisRound, this.profile, this.adjustedLevel, this.levelsDown,
      this.key);
}
