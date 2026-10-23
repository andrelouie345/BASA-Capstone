// lib/viewmodels/aral_roster_import_viewmodel.dart
//
// Imports an ARAL roster from a simple spreadsheet (piece IE5), e.g. for a
// school that started ARAL-Reading before BASA. Owner decision (2026-10-16):
// columns LRN, Program, Class, Entered (+ Notes); defaults agreed:
//  * .csv or the first sheet of an .xlsx; columns found by header name. The
//    roster CSV from aral-export-roster is itself a valid import file.
//  * The learner's section is their active enrollment in the school that
//    year. Program "KS3 Plus", "KS2 Basic", "KS1", "Foundational" (blank =
//    BASA's suggestion from results).
//  * Learners already on the roster are skipped (nothing is changed).
//  * Exited rows: a transfer/drop-out/other exit is entered and then exited on
//    its date; a grade-level-ready exit is skipped (BASA sets those from
//    results only).
//  * Class (ARAL classes, 2026-10-24; replaces "Tutor email"): the class's
//    name in that school and year; an unknown name is a row error. A class
//    that is full or teaches another program or grade band doesn't stop the
//    row: the learner is imported without a class (flagged in the preview).
//  * Every learner goes through AralViewModel.enroll (Grades 1-10, ...),
//    each section weakest reader first.
// Preview first, then import. Admins/coordinators of the school.
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/aral_rules.dart' show aralClassCap;
import '../core/services/normalizers.dart';
import '../core/services/table_reader.dart';
import 'aral_viewmodel.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

enum AralRosterImportOutcome { add, addAndExit, alreadyOnRoster, skipGradeLevelReady, error }

class AralRosterImportRow {
  final int rowNo;
  final String? lrn;
  final Student? student;
  final Section? section;
  final AralKeyStage? keyStage;      // null = BASA's suggestion
  final AralTrack? track;
  final AralClass? aralClass;        // the Class column's class; null = none given
  /// Why the learner goes in without the class asked for (full, another
  /// program or grade); null = placed in it.
  final String? classFlag;
  final String enteredOn;            // YYYY-MM-DD
  final String? exitedOn;
  final AralExitReason? exitReason;
  final String? notes;
  final AralRosterImportOutcome outcome;
  final List<String> problems;

  const AralRosterImportRow({
    required this.rowNo,
    this.lrn,
    this.student,
    this.section,
    this.keyStage,
    this.track,
    this.aralClass,
    this.classFlag,
    required this.enteredOn,
    this.exitedOn,
    this.exitReason,
    this.notes,
    required this.outcome,
    this.problems = const [],
  });

  String get name => student == null ? (lrn ?? '?') : '${student!.lastName}, ${student!.firstName}';
  String get program => keyStage == null
      ? "BASA's suggestion"
      : track == null
          ? keyStage!.label
          : '${keyStage!.label} ${track!.label}';
}

class AralRosterImportPreview {
  final int schoolId;
  final String schoolYear;
  final List<AralRosterImportRow> rows;
  final List<String> notes;
  const AralRosterImportPreview(this.schoolId, this.schoolYear, this.rows, this.notes);

  int count(AralRosterImportOutcome o) => rows.where((r) => r.outcome == o).length;
}

class AralRosterImportResult {
  final AralRosterImportPreview preview;
  final List<AralEnrollment> added;
  final Map<AralRosterImportRow, String> failed;
  /// Rows imported with a notice (e.g. without the class asked for).
  final Map<AralRosterImportRow, String> warnings;
  const AralRosterImportResult(this.preview, this.added, this.failed, [this.warnings = const {}]);
}

class AralRosterImportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralViewModel _aral;
  final AralEnrollmentRepository _roster;
  final AralClassRepository _classes;
  final SectionRepository _sections;
  final StudentRepository _students;

  AralRosterImportViewModel({
    required AuthViewModel auth,
    required AralViewModel aral,
    required AralEnrollmentRepository roster,
    required AralClassRepository classes,
    required SectionRepository sections,
    required StudentRepository students,
    Logger? logger,
  })  : _auth = auth,
        _aral = aral,
        _roster = roster,
        _classes = classes,
        _sections = sections,
        _students = students,
        _log = ScopedLogger(logger, 'AralRosterImportViewModel');

  Future<AralRosterImportPreview> preview(int schoolId, String schoolYear, List<int> bytes, String fileName) async {
    _log('preview(school: $schoolId, year: $schoolYear, file: $fileName)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can import an ARAL roster.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) throw const ViewModelException('Forbidden: that school is not yours.');
    schoolYear = normalizeSchoolYear(schoolYear);

    final List<String> headers;
    final List<TableRow> table;
    try {
      (headers, table) = readTable(bytes, fileName);
    } on TableReadException catch (e) {
      throw ViewModelException(e.message);
    }
    final known = headers.map(normalizeHeader).toSet();
    if (!known.contains('lrn')) throw ViewModelException('The file has no LRN column (columns: ${headers.join(', ')}).');
    final notes = <String>[];
    if (!known.contains('program')) notes.add('No Program column: every learner gets BASA\'s suggestion from results.');

    // The school's learners this year: LRN -> (student, section).
    final where = <String, (Student, Section)>{};
    for (final s in await _sections.getAll()) {
      if (s.schoolId != schoolId || s.schoolYear != schoolYear) continue;
      for (final st in await _students.getBySection(s.id!)) {
        where[st.lrn.trim()] = (st, s);
      }
    }
    // The school's classes this year, by name (as the cloud compares them),
    // and the places each still has; rows going in take them in file order.
    final classes = {
      for (final c in await _classes.getBySchool(schoolId, schoolYear: schoolYear)) c.className.trim().toLowerCase(): c,
    };
    final taken = <int, int>{
      for (final c in classes.values) c.id!: (await _roster.getByClass(c.id!)).where((e) => e.isActive).length,
    };
    final today = _date(DateTime.now());
    final seen = <String>{};
    final rows = <AralRosterImportRow>[];
    for (final t in table) {
      final problems = <String>[];
      final lrn = t.get(const ['LRN']);
      final found = lrn == null ? null : where[lrn];
      if (lrn == null) {
        problems.add('no LRN');
      } else if (found == null) {
        problems.add('LRN $lrn has no active enrollment in a section of school $schoolId for $schoolYear');
      } else if (!seen.add(lrn)) {
        problems.add('LRN $lrn appears twice in the file');
      }

      AralKeyStage? ks;
      AralTrack? track;
      final program = t.get(const ['Program', 'Placement']);
      if (program != null) {
        final p = _program(program);
        if (p == null) {
          problems.add('program "$program" is not Foundational, KS1, KS2 Basic/Plus or KS3 Basic/Plus');
        } else {
          (ks, track) = p;
        }
      }

      AralClass? cls;
      final className = t.get(const ['Class', 'ARAL class']);
      if (className != null) {
        cls = classes[className.trim().toLowerCase()];
        if (cls == null) problems.add('no ARAL class named "$className" in school $schoolId for $schoolYear on this device');
      }

      final enteredRaw = t.get(const ['Entered', 'Entered on', 'Date entered']);
      final entered = parseSheetDate(enteredRaw);
      if (enteredRaw != null && entered == null) problems.add('entered date "$enteredRaw" is not a date');
      if (entered != null && entered.compareTo(today) > 0) problems.add('entered date $entered is in the future');

      final exitedRaw = t.get(const ['Exited', 'Exited on', 'Date exited']);
      final reasonRaw = t.get(const ['Exit reason', 'Reason']);
      final status = t.get(const ['Status'])?.toLowerCase();
      final exitedOn = parseSheetDate(exitedRaw);
      AralExitReason? reason;
      final leaving = exitedRaw != null || reasonRaw != null || status == 'exited';
      if (leaving) {
        if (exitedOn == null) problems.add(exitedRaw == null ? 'exited without an exit date' : 'exit date "$exitedRaw" is not a date');
        reason = _reason(reasonRaw);
        if (reason == null) {
          problems.add(reasonRaw == null
              ? 'exited without an exit reason'
              : 'exit reason "$reasonRaw" is not grade-level ready, transferred out, dropped out, other or '
                  'classroom support');
        }
        final from = entered ?? today;
        if (exitedOn != null && exitedOn.compareTo(from) < 0) problems.add('exit date $exitedOn is before entry $from');
      }

      var outcome = leaving ? AralRosterImportOutcome.addAndExit : AralRosterImportOutcome.add;
      if (problems.isNotEmpty) {
        outcome = AralRosterImportOutcome.error;
      } else if (reason == AralExitReason.gradeLevelReady) {
        outcome = AralRosterImportOutcome.skipGradeLevelReady;
      } else if (await _roster.findForStudent(found!.$1.id!, schoolYear) != null) {
        outcome = AralRosterImportOutcome.alreadyOnRoster;
      }
      String? classFlag;
      if (cls != null && outcome == AralRosterImportOutcome.add) {
        final grade = int.tryParse(found!.$2.gradeLevel) ?? 0;
        if (ks != null && AralClassProgram.of(ks, track) != cls.program) {
          classFlag = 'class "${cls.className}" is ${cls.program.label}: imported without a class';
        } else if (!cls.gradeBand.contains(grade)) {
          classFlag = 'class "${cls.className}" takes Grades ${cls.gradeBand.value}: imported without a class';
        } else if (taken[cls.id!]! >= aralClassCap) {
          classFlag = 'class "${cls.className}" is full: imported without a class';
        } else {
          taken[cls.id!] = taken[cls.id!]! + 1;
        }
      }
      rows.add(AralRosterImportRow(
        rowNo: t.rowNo,
        lrn: lrn,
        student: found?.$1,
        section: found?.$2,
        keyStage: ks,
        track: track,
        aralClass: cls,
        classFlag: classFlag,
        enteredOn: entered ?? today,
        exitedOn: exitedOn,
        exitReason: reason,
        notes: t.get(const ['Notes', 'Remarks']),
        outcome: outcome,
        problems: problems,
      ));
    }
    if (rows.any((r) => r.outcome != AralRosterImportOutcome.error) &&
        table.any((t) => t.get(const ['Entered', 'Entered on', 'Date entered']) == null)) {
      notes.add('Rows without an Entered date are entered today ($today).');
    }
    return AralRosterImportPreview(schoolId, schoolYear, rows, notes);
  }

  Future<AralRosterImportResult> importRoster(int schoolId, String schoolYear, List<int> bytes, String fileName) async {
    final p = await preview(schoolId, schoolYear, bytes, fileName);
    _log('importRoster(school: $schoolId, year: ${p.schoolYear})');
    final todo = p.rows
        .where((r) => r.outcome == AralRosterImportOutcome.add || r.outcome == AralRosterImportOutcome.addAndExit)
        .toList();
    // Weakest reader first within each section (BASA's ranking), others after.
    final rank = <int, int>{};
    for (final sectionId in todo.map((r) => r.section!.id!).toSet()) {
      for (final c in await _aral.propose(sectionId: sectionId, schoolYear: p.schoolYear)) {
        if (c.rank != null) rank[c.student.id!] = c.rank!;
      }
    }
    todo.sort((a, b) {
      final s = a.section!.id!.compareTo(b.section!.id!);
      return s != 0 ? s : (rank[a.student!.id] ?? 1 << 20).compareTo(rank[b.student!.id] ?? 1 << 20);
    });

    final added = <AralEnrollment>[];
    final failed = <AralRosterImportRow, String>{};
    final warnings = <AralRosterImportRow, String>{};
    for (final r in todo) {
      try {
        var e = await _aral.enroll(
          sectionId: r.section!.id!,
          schoolYear: p.schoolYear,
          studentId: r.student!.id!,
          keyStage: r.keyStage,
          track: r.track,
          // An exited row goes in without a class: it would only hold a place.
          classId: r.classFlag == null && r.outcome == AralRosterImportOutcome.add ? r.aralClass?.id : null,
          notes: r.notes,
          enteredOn: DateTime.parse(r.enteredOn),
        );
        final warning = _aral.lastWarning ?? r.classFlag;
        if (warning != null) warnings[r] = warning;
        if (r.outcome == AralRosterImportOutcome.addAndExit) {
          e = await _aral.exit(e.id!, r.exitReason!, on: DateTime.parse(r.exitedOn!));
        }
        added.add(e);
      } catch (e) {
        failed[r] = '$e';
      }
    }
    return AralRosterImportResult(p, added, failed, warnings);
  }

  /// "KS3 Plus", "ks2 basic", "KS1", "Foundational" -> (key stage, track).
  static (AralKeyStage, AralTrack?)? _program(String raw) {
    final words = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().split(' ');
    AralKeyStage? ks;
    AralTrack? track;
    for (final w in words) {
      switch (w) {
        case 'foundational' || 'foundation':
          ks = AralKeyStage.foundational;
        case 'ks1' || 'ks2' || 'ks3':
          ks = AralKeyStage.fromString(w);
        case 'basic':
          track = AralTrack.basic;
        case 'plus':
          track = AralTrack.plus;
      }
    }
    if (ks == null) return null;
    if (ks.hasTrack != (track != null)) return null;
    return (ks, track);
  }

  static AralExitReason? _reason(String? raw) {
    if (raw == null) return null;
    final s = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return switch (s) {
      'gradelevelready' || 'glr' => AralExitReason.gradeLevelReady,
      'transferredout' || 'transferred' || 'transfer' => AralExitReason.transferredOut,
      'droppedout' || 'dropped' || 'dropout' => AralExitReason.droppedOut,
      'other' || 'others' => AralExitReason.other,
      'classroomsupport' || 'exitwithclassroomsupport' || 'classroom' => AralExitReason.classroomSupport,
      _ => null,
    };
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
