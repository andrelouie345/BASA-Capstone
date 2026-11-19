// lib/viewmodels/aral_forms_viewmodel.dart
//
// ARAL Forms 1, 2 and 4 (Reading) of Division Memorandum 180 s. 2026, read
// from the device copy (ARAL memo Plan B Task 5; spec
// docs/superpowers/specs/2026-11-18-aral-division-memo-design.md section 8).
// Admin build, read-only. Only the memo's PDF exists, so the forms copy its
// header fields and columns; what BASA doesn't hold is left blank for hand
// entry and listed in each form's footer (`blanks` / `notes`).
//
// Results come from AralReportViewModel.learnerRounds, the implementation
// report's own per-learner results (same rules, same value source). Owner
// decisions 2026-11-19:
//  * Phil-IRI result words: 3+ levels down, Non-Reader, not assessed ->
//    Frustration; 1-2 down -> Instructional; at grade level -> Grade level.
//  * A learner without a MoSY result of their own (Phil-IRI carries BoSY
//    into the report's MoSY column) has a blank MoSY tool and result.
//  * Form 2 class result: the one result every learner shares; none -> blank;
//    else "mixed".
//  * Tutor counts: distinct tutors of the school's classes that year, by type.
//  * Form 4: identified = basis round BoSY; served = placed in a class and
//    marked present at least once by the date; improved = own MoSY result
//    ranked above BoSY; everything else still in ARAL = No improvement
//    (learners without a MoSY result, and those with a MoSY result but no
//    BoSY result, named in the notes; review I1).
import '../core/console/logger.dart';
import '../core/models/aral_forms.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_session.dart';
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_forms_xlsx.dart';
import '../core/services/auth_messages.dart';
import '../core/services/normalizers.dart';
import '../core/services/xlsx_cells.dart' show XlsxException;
import 'aral_report_viewmodel.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

export '../core/models/aral_forms.dart';

/// The form's word for one learner's report result ('' = none).
String aralFormResult(AralLearnerRounds x, String? result) {
  if (result == null || result == aralReportNoResult) return '';
  if (x.instrument == AralLearnerRounds.crla) return result;
  if (result == aralReportNotAssessed || result == 'Non-Reader') return aralFormFrustration;
  if (result == 'GLR') return aralFormGradeLevel;
  final down = int.tryParse(RegExp(r'^(\d+)-LD$').firstMatch(result)?.group(1) ?? '');
  if (down == null) return '';
  return down >= 3 ? aralFormFrustration : aralFormInstructional;
}

class AralFormsViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralReportViewModel _report;
  final AralClassRepository _classes;
  final AralEnrollmentRepository _roster;
  final AralSessionRepository _sessions;
  final UserRepository _users;
  final SectionRepository _sections;
  final StudentRepository _students;
  final SchoolRepository _schools;

  AralFormsViewModel({
    required AuthViewModel auth,
    required AralReportViewModel report,
    required AralClassRepository classes,
    required AralEnrollmentRepository roster,
    required AralSessionRepository sessions,
    required UserRepository users,
    required SectionRepository sections,
    required StudentRepository students,
    required SchoolRepository schools,
    Logger? logger,
  })  : _auth = auth,
        _report = report,
        _classes = classes,
        _roster = roster,
        _sessions = sessions,
        _users = users,
        _sections = sections,
        _students = students,
        _schools = schools,
        _log = ScopedLogger(logger, 'AralFormsViewModel');

  static const form1Blanks = ['district', 'workbook issued', 'remarks', 'signatures'];
  static const form2Blanks = ['district', 'Mathematics columns', 'signatures'];
  static const form4Blanks = ['Mathematics columns', 'narrative rows', 'signatures'];

  /// Form 1 of one class ([classId]) or of every class of the school and
  /// year (by class name), with the class's active learners and their MoSY
  /// result as of today.
  Future<List<AralForm1>> form1({required int schoolId, required String schoolYear, int? classId}) async {
    _log('form1(school: $schoolId, year: $schoolYear, class: ${classId ?? 'all'})');
    _requireManager(schoolId);
    final year = normalizeSchoolYear(schoolYear);
    final ctx = await _context(schoolId, year, asOf: null);
    var classes = ctx.classes;
    if (classId != null) {
      classes = classes.where((c) => c.id == classId).toList();
      if (classes.isEmpty) {
        throw ViewModelException("That class is not one of this school's ARAL classes for $year.");
      }
    }
    final out = <AralForm1>[];
    for (final c in classes) {
      final tutor = ctx.tutor(c);
      out.add(AralForm1(
        schoolName: ctx.schoolName,
        schoolCode: ctx.schoolCode,
        classCode: c.className,
        grade: c.gradeLevel,
        tutorName: tutor?.fullName ?? '',
        tutorType: switch (tutor?.tutorType) {
          TutorType.internal => 'Internal',
          TutorType.external => 'External',
          null => '',
        },
        sessionType: c.sessionType?.label ?? '',
        schedule: c.schedule ?? '',
        venue: c.room ?? '',
        rows: [
          for (final e in await ctx.learnersOf(c))
            () {
              final x = ctx.rounds[e.id];
              final own = x != null && x.mosyOwn;
              final student = ctx.students[e.studentId];
              final section = ctx.sections[e.sectionId];
              return AralForm1Row(
                lrn: student?.lrn ?? '',
                name: _name(student),
                sex: _sex(student),
                homeGrade: int.tryParse(section?.gradeLevel ?? ''),
                section: section?.sectionName ?? '',
                adviser: section?.adviserName ?? '',
                mosyTool: own ? x.instrument : '',
                mosyResult: own ? aralFormResult(x, x.mosyResult) : '',
              );
            }(),
        ],
        blanks: form1Blanks,
      ));
    }
    return out;
  }

  /// Form 2: one row per ARAL class of the school and year, as of today.
  Future<AralForm2> form2({required int schoolId, required String schoolYear}) async {
    _log('form2(school: $schoolId, year: $schoolYear)');
    _requireManager(schoolId);
    final year = normalizeSchoolYear(schoolYear);
    final ctx = await _context(schoolId, year, asOf: null);
    final rows = <AralForm2Row>[];
    for (final c in ctx.classes) {
      final learners = await ctx.learnersOf(c);
      final students = [for (final e in learners) ctx.students[e.studentId]];
      final results = {
        for (final e in learners)
          () {
            final x = ctx.rounds[e.id];
            return x != null && x.mosyOwn ? aralFormResult(x, x.mosyResult) : '';
          }(),
      };
      final tutor = ctx.tutor(c);
      final advisory = tutor == null
          ? <String>[]
          : (ctx.allSections.where((s) => s.adviserUserId == tutor.id).toList()
                ..sort((a, b) {
                  final g = (int.tryParse(a.gradeLevel) ?? 0).compareTo(int.tryParse(b.gradeLevel) ?? 0);
                  return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
                }))
              .map((s) => 'Grade ${s.gradeLevel} ${s.sectionName}')
              .toList();
      rows.add(AralForm2Row(
        classCode: c.className,
        grade: c.gradeLevel,
        male: students.where((s) => _sex(s) == 'M').length,
        female: students.where((s) => _sex(s) == 'F').length,
        total: learners.length,
        mosyResult: results.isEmpty || (results.length == 1 && results.single == '')
            ? ''
            : results.length == 1
                ? results.single
                : aralFormMixed,
        tutorName: tutor?.fullName ?? '',
        tutorType: switch (tutor?.tutorType) {
          TutorType.internal => 'I',
          TutorType.external => 'E',
          null => '',
        },
        advisoryClass: advisory.join(', '),
        schedule: c.schedule ?? '',
        sessionType: c.sessionType?.label ?? '',
        venue: c.room ?? '',
      ));
    }
    final (internal, external, untyped) = ctx.tutorCounts();
    return AralForm2(
      schoolName: ctx.schoolName,
      schoolCode: ctx.schoolCode,
      rows: rows,
      readingClasses: rows.length,
      readingLearners: rows.fold(0, (a, r) => a + r.total),
      internalTutors: internal,
      externalTutors: external,
      blanks: form2Blanks,
      notes: [if (untyped.isNotEmpty) _untypedNote(untyped)],
    );
  }

  /// Form 4 as of [asOf] (YYYY-MM-DD): Part I per grade 1-10 (Reading),
  /// Part II classes, tutors, sessions and hours.
  Future<AralForm4> form4({required int schoolId, required String schoolYear, required String asOf}) async {
    _log('form4(school: $schoolId, year: $schoolYear, asOf: $asOf)');
    _requireManager(schoolId);
    final year = normalizeSchoolYear(schoolYear);
    final ctx = await _context(schoolId, year, asOf: asOf);
    final date = ctx.asOf;

    final held = (await _sessions.getBySchool(schoolId, schoolYear: year))
        .where((s) => s.heldOn.compareTo(date) <= 0)
        .toList();
    final present = <int>{};
    for (final s in held) {
      for (final a in await _sessions.getAttendance(s.id!)) {
        if (a.mark == AralMark.present) present.add(a.enrollmentId);
      }
    }

    final grades = [for (var g = 1; g <= 10; g++) AralForm4Grade(g)];
    final noMosy = <String>[];
    final noBosy = <String>[];
    for (final x in ctx.rounds.values) {
      if (x.grade < 1 || x.grade > 10) continue;
      final row = grades[x.grade - 1];
      final e = x.enrollment;
      if (e.basisRound == 'bosy') row.identified++;
      if (e.classId != null && present.contains(e.id)) row.served++;
      if (!x.inAral) {
        if (e.exitReason == AralExitReason.gradeLevelReady) row.reachedGradeLevel++;
        continue;
      }
      row.atMosy++;
      final b = x.bosyRank, m = x.mosyRank;
      if (x.mosyOwn && b != null && m != null && m > b) {
        row.improved++;
      } else {
        row.noImprovement++;
        final who = '${_name(ctx.students[e.studentId])} (Grade ${x.grade})';
        if (!x.mosyOwn) {
          noMosy.add(who);
        } else if (b == null) {
          // e.g. Grade 1: CRLA starts at MoSY (review I1, owner 2026-11-19: named).
          noBosy.add(who);
        }
      }
    }

    final (internal, external, untyped) = ctx.tutorCounts();
    final minutes = held.fold(0, (a, s) => a + s.minutes);
    noMosy.sort();
    noBosy.sort();
    return AralForm4(
      schoolName: ctx.schoolName,
      schoolCode: ctx.schoolCode,
      asOf: date,
      grades: grades,
      classes: ctx.classes.length,
      internalTutors: internal,
      externalTutors: external,
      sessions: held.length,
      hours: minutes / 60,
      notes: [
        if (noMosy.isNotEmpty)
          '${_learners(noMosy.length)} without a MoSY result by $date ${noMosy.length == 1 ? 'is' : 'are'} '
              'counted under No improvement: ${noMosy.join('; ')}.',
        if (noBosy.isNotEmpty)
          '${_learners(noBosy.length)} without a BoSY result by $date ${noBosy.length == 1 ? 'is' : 'are'} '
              'counted under No improvement: ${noBosy.join('; ')}.',
        if (untyped.isNotEmpty) _untypedNote(untyped),
        'Left blank for hand entry: ${form4Blanks.join(', ')}.',
      ],
    );
  }

  /// [form1] as an .xlsx file: one sheet per class.
  Future<List<int>> form1Xlsx({required int schoolId, required String schoolYear, int? classId}) async {
    final forms = await form1(schoolId: schoolId, schoolYear: schoolYear, classId: classId);
    if (forms.isEmpty) {
      throw ViewModelException('This school has no ARAL classes for ${normalizeSchoolYear(schoolYear)} yet.');
    }
    return _xlsx(() => aralForm1Xlsx(forms));
  }

  /// [form2] as an .xlsx file.
  Future<List<int>> form2Xlsx({required int schoolId, required String schoolYear}) async {
    final form = await form2(schoolId: schoolId, schoolYear: schoolYear);
    return _xlsx(() => aralForm2Xlsx(form));
  }

  /// [form4] as an .xlsx file.
  Future<List<int>> form4Xlsx({required int schoolId, required String schoolYear, required String asOf}) async {
    final form = await form4(schoolId: schoolId, schoolYear: schoolYear, asOf: asOf);
    return _xlsx(() => aralForm4Xlsx(form));
  }

  static List<int> _xlsx(List<int> Function() write) {
    try {
      return write();
    } on XlsxException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  // --- helpers ---

  void _requireManager(int schoolId) {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: only an admin or coordinator can make the ARAL forms.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Not allowed: that school is not yours.');
    }
  }

  Future<_FormContext> _context(int schoolId, String year, {required String? asOf}) async {
    final school = await _schools.getById(schoolId);
    final list = await _report.learnerRounds(schoolId: schoolId, schoolYear: year, asOf: asOf);
    final classes = (await _classes.getBySchool(schoolId, schoolYear: year))
        .where((c) => c.schoolYear == year)
        .toList()
      ..sort((a, b) => a.className.toLowerCase().compareTo(b.className.toLowerCase()));
    final users = <String, User?>{};
    for (final id in classes.map((c) => c.tutorId).whereType<String>().toSet()) {
      users[id] = await _users.getById(id);
    }
    final allSections =
        (await _sections.getAll()).where((s) => s.schoolId == schoolId && s.schoolYear == year).toList();
    return _FormContext(
      schoolName: school?.schoolName ?? '',
      schoolCode: school?.schoolId ?? '',
      asOf: asOf ?? _today(), // learnerRounds has checked its shape
      classes: classes,
      rounds: {for (final x in list) x.enrollmentId: x},
      students: {for (final s in await _students.getAll('id')) s.id!: s},
      sections: {for (final s in allSections) s.id!: s},
      allSections: allSections,
      users: users,
      roster: _roster,
    );
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _name(Student? s) {
    if (s == null) return '';
    final middle = s.middleName?.trim() ?? '';
    final mi = middle.isEmpty ? '' : ' ${middle[0].toUpperCase()}.';
    return '${s.lastName}, ${s.firstName}$mi';
  }

  static String _sex(Student? s) {
    final v = s?.sex?.trim().toUpperCase() ?? '';
    return v == 'M' || v == 'F' ? v : '';
  }

  static String _learners(int n) => n == 1 ? '1 learner' : '$n learners';

  static String _untypedNote(List<String> names) =>
      'Tutor type not set (counted as neither internal nor external): ${names.join('; ')}.';
}

class _FormContext {
  final String schoolName;
  final String schoolCode;
  final String asOf;
  final List<AralClass> classes;
  final Map<int, AralLearnerRounds> rounds; // by aral_enrollments.id
  final Map<int, Student> students;
  final Map<int, Section> sections;
  final List<Section> allSections;
  final Map<String, User?> users;
  final AralEnrollmentRepository roster;

  _FormContext({
    required this.schoolName,
    required this.schoolCode,
    required this.asOf,
    required this.classes,
    required this.rounds,
    required this.students,
    required this.sections,
    required this.allSections,
    required this.users,
    required this.roster,
  });

  User? tutor(AralClass c) => c.tutorId == null ? null : users[c.tutorId];

  /// The class's active learners, by last name then first name.
  Future<List<AralEnrollment>> learnersOf(AralClass c) async {
    final list = (await roster.getByClass(c.id!)).where((e) => e.isActive && e.schoolYear == c.schoolYear).toList();
    String key(AralEnrollment e) {
      final s = students[e.studentId];
      return '${s?.lastName.toLowerCase() ?? ''}\u0000${s?.firstName.toLowerCase() ?? ''}';
    }

    list.sort((a, b) => key(a).compareTo(key(b)));
    return list;
  }

  /// Distinct tutors of the classes: internal, external, and names without a type.
  (int, int, List<String>) tutorCounts() {
    var internal = 0, external = 0;
    final untyped = <String>[];
    for (final u in users.values.whereType<User>()) {
      switch (u.tutorType) {
        case TutorType.internal:
          internal++;
        case TutorType.external:
          external++;
        case null:
          untyped.add(u.fullName);
      }
    }
    untyped.sort();
    return (internal, external, untyped);
  }
}
