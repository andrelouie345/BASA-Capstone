// lib/core/services/sf1_importer.dart
import 'dart:convert';
import 'dart:io';
import 'package:basa_capstone/core/services/xls_to_xlsx_converter.dart';
import 'package:excel_plus/excel_plus.dart';
import '../console/logger.dart';
import '../models/school.dart';
import '../models/section.dart';
import '../models/student.dart';
import '../models/import_conflict.dart';
import '../models/region.dart';
import '../repositories/school_repository.dart';
import '../repositories/section_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/import_conflict_repository.dart';
import 'sf1_column_map.dart';
import 'normalizers.dart';

class Sf1ImportResult {
  int inserted = 0;
  int conflicts = 0;
  int alreadyEnrolled = 0;
  int skippedBlankOrTotal = 0;
}

/// One parsed data row's outcome, before any write happens.
class Sf1TrialRow {
  final int rowIndex;
  final String? lrn;
  final String name;
  final String outcome; // 'insert' | 'conflict' | 'enrolled' (already in this section) | 'skip'
  final String? reason;
  final int? existingStudentId; // set only when outcome == 'conflict'

  Sf1TrialRow({
    required this.rowIndex,
    required this.lrn,
    required this.name,
    required this.outcome,
    this.reason,
    this.existingStudentId,
  });
}

/// Everything import() needs, computed read-only — shared by both
/// import() (which then performs writes) and trial() (which doesn't).
class Sf1TrialResult {
  final String? rawRegion;
  final int? regionId;
  final String? regionError;
  final String schoolIdCode;
  final String schoolName;
  final String schoolYear;
  final String gradeLevel;
  final String sectionName;
  final List<Sf1TrialRow> rows;
  final Map<int, Student> parsedStudents; // rowIndex -> parsed Student, insert+conflict rows only

  Sf1TrialResult({
    required this.rawRegion,
    required this.regionId,
    required this.regionError,
    required this.schoolIdCode,
    required this.schoolName,
    required this.schoolYear,
    required this.gradeLevel,
    required this.sectionName,
    required this.rows,
    required this.parsedStudents,
  });

  int get wouldInsert => rows.where((r) => r.outcome == 'insert').length;
  int get wouldConflict => rows.where((r) => r.outcome == 'conflict').length;
  int get wouldSkip => rows.where((r) => r.outcome == 'skip').length;
  int get alreadyEnrolled => rows.where((r) => r.outcome == 'enrolled').length;
}

/// Reason recorded for a row whose LRN belongs to a learner in another school.
const transferConflictReason =
    'LRN registered at another school (transfer) - only the superadmin can resolve';

class Sf1Importer {
  final SchoolRepository schoolRepo;       // Supabase — source of truth
  final SchoolRepository localSchoolRepo;  // SQLite — mirror
  final SectionRepository sectionRepo;
  final SectionRepository localSectionRepo;
  final StudentRepository studentRepo;
  final StudentRepository localStudentRepo;
  final ImportConflictRepository conflictRepo; // Supabase only, no local mirror
  final Sf1ColumnMap columnMap;
  final ScopedLogger _log;
  final XlsToXlsxConverter _converter;

  Sf1Importer({
    required this.schoolRepo,
    required this.localSchoolRepo,
    required this.sectionRepo,
    required this.localSectionRepo,
    required this.studentRepo,
    required this.localStudentRepo,
    required this.conflictRepo,
    required this.columnMap,
    Logger? logger,
  })  : _log = ScopedLogger(logger, 'Sf1Importer'),
        _converter = XlsToXlsxConverter(logger: logger);

  Future<String> _resolveToXlsx(String filePath) async {
    if (filePath.toLowerCase().endsWith('.xls')) {
      return _converter.convert(filePath);
    }
    return filePath;
  }

  Future<Excel> _decodeWithRepair(String filePath) async {
    try {
      final bytes = File(filePath).readAsBytesSync();
      return Excel.decodeBytes(bytes);
    } catch (e) {
      _log('Failed to decode Excel file, likely because xls. Will make an xlsx copy: $e');
      final xlsxPath = await _resolveToXlsx(filePath);
      final bytes = File(xlsxPath).readAsBytesSync();
      return Excel.decodeBytes(bytes);
    }
  }

  String? _cell(Sheet sheet, int row, int col) {
    if (row >= sheet.maxRows || col >= sheet.maxColumns) return null;
    final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value;
    if (v == null) return null;
    return v.toString().trim().isEmpty ? null : v.toString().trim();
  }

  Future<List<String?>> previewRow(String filePath, int rowIndex) async {
    final excelFile = await _decodeWithRepair(filePath);
    final sheet = excelFile.tables[excelFile.tables.keys.first]!;
    return List.generate(sheet.maxColumns, (c) => _cell(sheet, rowIndex, c));
  }

  String? _normalizeDate(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final mm = parts[0].padLeft(2, '0');
    final dd = parts[1].padLeft(2, '0');
    final yyyy = parts[2];
    return '$yyyy-$mm-$dd';
  }

  bool _isTotalRow(String? nameCell) =>
      nameCell != null && nameCell.toUpperCase().contains('TOTAL');

  bool _hasMergedName(String cell) => cell.contains(',');

  // Returns [last, first, middle, suffix] with blanks collapsed to null.
  List<String?> _splitMergedName(String raw) {
    final parts = raw.split(',').map((p) => p.trim()).toList();
    return List.generate(4, (i) {
      if (i >= parts.length) return null;
      final v = parts[i];
      return v.isEmpty ? null : v;
    });
  }

  /// Parses the sheet and checks for LRN conflicts (read-only — findByLrn
  /// is a lookup, never a write). Does NOT create anything. Shared by
  /// import() and trial(), so the two can never drift apart on what
  /// counts as "would insert" vs "would conflict" vs "would skip".
  Future<Sf1TrialResult> _parseSheet(Excel excelFile) async {
    final sheet = excelFile.tables[excelFile.tables.keys.first]!;

    final rawRegion = _cell(sheet, columnMap.regionRow, columnMap.regionCol);
    final regionId = Region.resolve(rawRegion);

    final schoolIdCode = _cell(sheet, columnMap.schoolIdRow, columnMap.schoolIdCol) ?? 'UNKNOWN';
    final schoolName = _cell(sheet, columnMap.schoolNameRow, columnMap.schoolNameCol) ?? 'UNKNOWN';
    final schoolYear = normalizeSchoolYear(_cell(sheet, columnMap.schoolYearRow, columnMap.schoolYearCol) ?? '');
    final gradeLevel = normalizeGradeLevel(_cell(sheet, columnMap.gradeLevelRow, columnMap.gradeLevelCol) ?? 'UNKNOWN');
    final sectionName = _cell(sheet, columnMap.sectionNameRow, columnMap.sectionNameCol) ?? 'UNKNOWN';

    // Learners already enrolled in this exact section (re-import of the same
    // roster): skipped instead of raised as conflicts. Read-only lookups, so
    // trial() reports it too.
    final existingSchool = await schoolRepo.getByCode(schoolIdCode);
    final existingSection = existingSchool == null
        ? null
        : await sectionRepo.findExisting(Section(
            schoolId: existingSchool.id!,
            schoolYear: schoolYear,
            gradeLevel: gradeLevel,
            sectionName: sectionName,
          ));
    final enrolledLrns = existingSection == null
        ? <String>{}
        : (await studentRepo.getBySection(existingSection.id!)).map((s) => s.lrn).toSet();

    final rows = <Sf1TrialRow>[];
    final parsedStudents = <int, Student>{};


    for (var row = columnMap.dataStartRow; row < sheet.maxRows; row++) {
      final lrn = _cell(sheet, row, columnMap.lrn);
      final lastName = _cell(sheet, row, columnMap.lastName);
      final sex = _cell(sheet, row, columnMap.sex);

      if (lrn == null || lastName == null || sex == null || _isTotalRow(lastName)) {
        rows.add(Sf1TrialRow(
          rowIndex: row,
          lrn: lrn,
          name: lastName ?? '',
          outcome: 'skip',
          reason: 'blank or total row',
        ));
        continue;
      }

      final Student parsed;
      final String? lName ;
      final String? fName ;
      final String? mName ;
      if (_hasMergedName(lastName)) {
        final n = _splitMergedName(lastName);
        lName = n[0] ?? '';
        fName = n[1] ?? '';
        mName = n[2];
      } else {
        lName = lastName;
        fName = _cell(sheet, row, columnMap.firstName) ?? '';
        mName = _cell(sheet, row, columnMap.middleName);
      }
      parsed = Student(
          lrn: lrn,
          lastName: lName,
          firstName: fName,
          middleName: mName,
          sex: sex,
          birthDate: _normalizeDate(_cell(sheet, row, columnMap.birthDate)),
          motherTongue: _cell(sheet, row, columnMap.motherTongue),
          ipGroup: _cell(sheet, row, columnMap.ipGroup),
          religion: _cell(sheet, row, columnMap.religion),
          addressStreet: _cell(sheet, row, columnMap.addressStreet),
          barangay: _cell(sheet, row, columnMap.barangay),
          municipality: _cell(sheet, row, columnMap.municipality),
          province: _cell(sheet, row, columnMap.province),
          fatherName: _cell(sheet, row, columnMap.fatherName),
          motherMaidenName: _cell(sheet, row, columnMap.motherMaidenName),
          guardianName: _cell(sheet, row, columnMap.guardianName),
          guardianRelationship: _cell(sheet, row, columnMap.guardianRelationship),
          contactNumber: _cell(sheet, row, columnMap.contactNumber),
          learningModality: _cell(sheet, row, columnMap.learningModality),
          remarks: _cell(sheet, row, columnMap.remarks),
        );

      final displayName =
          '${parsed.lastName}, ${parsed.firstName}${parsed.middleName != null ? " ${parsed.middleName}" : ""}';
      final existing = await studentRepo.findByLrn(lrn);

      if (enrolledLrns.contains(lrn)) {
        rows.add(Sf1TrialRow(
            rowIndex: row, lrn: lrn, name: displayName, outcome: 'enrolled', reason: 'already enrolled in this section'));
      } else if (existing == null) {
        // May still be a transfer: a learner in another school is invisible
        // here (RLS) and only shows up as a duplicate LRN at insert time.
        rows.add(Sf1TrialRow(rowIndex: row, lrn: lrn, name: displayName, outcome: 'insert'));
      } else {
        rows.add(Sf1TrialRow(
          rowIndex: row,
          lrn: lrn,
          name: displayName,
          outcome: 'conflict',
          reason: 'LRN already exists (existing student id ${existing.id})',
          existingStudentId: existing.id,
        ));
      }
      parsedStudents[row] = parsed;
    }

    return Sf1TrialResult(
      rawRegion: rawRegion,
      regionId: regionId,
      regionError: regionId == null
          ? 'Could not resolve region from cell value "${rawRegion ?? "(empty)"}" '
              '(row ${columnMap.regionRow}, col ${columnMap.regionCol})'
          : null,
      schoolIdCode: schoolIdCode,
      schoolName: schoolName,
      schoolYear: schoolYear,
      gradeLevel: gradeLevel,
      sectionName: sectionName,
      rows: rows,
      parsedStudents: parsedStudents,
    );
  }

  /// Parses and reports what import() WOULD do, without writing anything
  /// anywhere — no Supabase writes, no local mirror writes. Safe to run
  /// as many times as you like, including against files you're not sure
  /// about yet.
  Future<Sf1TrialResult> trial(String filePath) async {
    _log('trial($filePath)');
    final excelFile = await _decodeWithRepair(filePath);
    return _parseSheet(excelFile);
  }

  Future<Sf1ImportResult> import(String filePath) async {
    _log('import($filePath)');
    final result = Sf1ImportResult();

    final excelFile = await _decodeWithRepair(filePath);
    final parsed = await _parseSheet(excelFile);

    if (parsed.regionId == null) {
      throw Exception('${parsed.regionError}. Fix the source file or the Region matcher, then retry.');
    }
    _log('resolved region: ${Region.byId(parsed.regionId!)}');

    final school = await schoolRepo.getOrCreate(School(
      schoolId: parsed.schoolIdCode,
      schoolName: parsed.schoolName,
      regionId: parsed.regionId,
    ));
    await localSchoolRepo.upsertWithId(school);

    final section = await sectionRepo.getOrCreate(Section(
      schoolId: school.id!,
      schoolYear: parsed.schoolYear,
      gradeLevel: parsed.gradeLevel,
      sectionName: parsed.sectionName,
    ));
    await localSectionRepo.upsertWithId(section);
    _log('resolved section: $section (id=${section.id})');

    // A re-import must not stack a second identical pending conflict.
    final pendingHere = (await conflictRepo.getPending())
        .where((c) => c.sectionId == section.id)
        .map((c) => c.lrn)
        .toSet();
    Future<void> logConflict(String lrn, String reason, Student incoming, {int? existingStudentId}) async {
      if (pendingHere.add(lrn)) {
        await conflictRepo.log(ImportConflict(
          lrn: lrn,
          sectionId: section.id,
          reason: reason,
          incomingDataJson: jsonEncode(incoming.toMap()),
          existingStudentId: existingStudentId,
        ));
      } else {
        _log('conflict for LRN $lrn already pending in this section — not logged again');
      }
      result.conflicts++;
    }

    for (final row in parsed.rows) {
      if (row.outcome == 'skip') {
        result.skippedBlankOrTotal++;
        continue;
      }
      if (row.outcome == 'enrolled') {
        result.alreadyEnrolled++;
        continue;
      }

      final studentParsed = parsed.parsedStudents[row.rowIndex]!;

      if (row.outcome == 'insert') {
        // Insert with the section's school: RLS only lets a school admin
        // create (and read back) students of their own school.
        final Student inserted;
        try {
          inserted = await studentRepo.insert(
              Student.fromMap({...studentParsed.toMap(), 'school_id': section.schoolId}));
        } on DuplicateLrnException {
          // The LRN exists in a school we can't see: a transfer. Logged for a
          // superadmin, who can see both schools, to resolve.
          await logConflict(row.lrn!, transferConflictReason, studentParsed);
          _log('conflict flagged: LRN ${row.lrn} is registered at another school');
          continue;
        }
        final enrollmentId = await studentRepo.enroll(
          studentId: inserted.id!,
          sectionId: section.id!,
          schoolYear: section.schoolYear,
        );
        await localStudentRepo.upsertWithId(inserted);
        await localStudentRepo.enroll(
          studentId: inserted.id!,
          sectionId: section.id!,
          schoolYear: section.schoolYear,
          id: enrollmentId,
        );

        result.inserted++;
      } else {
        // conflict
        await logConflict(row.lrn!, row.reason!, studentParsed, existingStudentId: row.existingStudentId);
        _log('conflict flagged: LRN ${row.lrn} already exists');
      }
    }

    _log('done: ${result.inserted} inserted, ${result.conflicts} conflicts, '
        '${result.alreadyEnrolled} already enrolled, ${result.skippedBlankOrTotal} skipped');
    return result;
  }
}