// lib/core/services/sf1_importer.dart
import 'dart:convert';
import 'dart:io';
// import 'package:basa_capstone/core/services/xlsx_repair_service.dart'; removed
import 'package:basa_capstone/core/services/xls_to_xlsx_converter.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:sqflite_common/sqflite.dart';
import '../console/logger.dart';
import '../models/school.dart';
import '../models/section.dart';
import '../models/student.dart';
import '../models/import_conflict.dart';
import '../repositories/school_repository.dart';
import '../repositories/section_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/import_conflict_repository.dart';
import 'sf1_column_map.dart';

class Sf1ImportResult {
  int inserted = 0;
  int conflicts = 0;
  int skippedBlankOrTotal = 0;
}

class Sf1Importer {
  final SchoolRepository schoolRepo;
  final SectionRepository sectionRepo;
  final StudentRepository studentRepo;
  final ImportConflictRepository conflictRepo;
  final ScopedLogger _log;
  final XlsToXlsxConverter _converter;

  Sf1Importer({
    required this.schoolRepo,
    required this.sectionRepo,
    required this.studentRepo,
    required this.conflictRepo,
    Logger? logger,
  }) : 
  _log = ScopedLogger(logger, 'Sf1Importer'),
  _converter = XlsToXlsxConverter(logger: logger);


  Future<String> _resolveToXlsx(String filePath) async {
    if (filePath.toLowerCase().endsWith('.xls')) {
      return _converter.convert(filePath);
    }
    return filePath; // already .xlsx
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

  /// For verifying column mapping before a real import.
  Future<List<String?>> previewRow(String filePath, int rowIndex) async {
    final bytes = File(filePath).readAsBytesSync();
    final excelFile = await _decodeWithRepair(filePath);
    final sheet = excelFile.tables[excelFile.tables.keys.first]!;
    return List.generate(sheet.maxColumns, (c) => _cell(sheet, rowIndex, c));
  }

  String? _normalizeDate(String? raw) {
    if (raw == null) return null;
    // Expects mm-dd-yyyy per sample data — adjust if your converted file differs.
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final mm = parts[0].padLeft(2, '0');
    final dd = parts[1].padLeft(2, '0');
    final yyyy = parts[2];
    return '$yyyy-$mm-$dd';
  }

  bool _isTotalRow(String? nameCell) =>
      nameCell != null && nameCell.toUpperCase().contains('TOTAL');

  Future<Sf1ImportResult> import(String filePath) async {
    _log('import($filePath)');
    final result = Sf1ImportResult();

    final bytes = File(filePath).readAsBytesSync();
    final excelFile = await _decodeWithRepair(filePath);
    final sheet = excelFile.tables[excelFile.tables.keys.first]!;

    // 1. Metadata -> get-or-create school + section
    final school = await schoolRepo.getOrCreate(School(
      schoolId: _cell(sheet, Sf1ColumnMap.schoolIdRow, Sf1ColumnMap.schoolIdCol) ?? 'UNKNOWN',
      schoolName: _cell(sheet, Sf1ColumnMap.schoolNameRow, Sf1ColumnMap.schoolNameCol) ?? 'UNKNOWN',
    ));

    final section = await sectionRepo.getOrCreate(Section(
      schoolId: school.id!,
      schoolYear: _cell(sheet, Sf1ColumnMap.schoolYearRow, Sf1ColumnMap.schoolYearCol) ?? 'UNKNOWN',
      gradeLevel: _cell(sheet, Sf1ColumnMap.gradeLevelRow, Sf1ColumnMap.gradeLevelCol) ?? 'UNKNOWN',
      sectionName: _cell(sheet, Sf1ColumnMap.sectionNameRow, Sf1ColumnMap.sectionNameCol) ?? 'UNKNOWN',
    ));

    _log('resolved section: $section (id=${section.id})');

    // 2. Student rows
    for (var row = Sf1ColumnMap.dataStartRow; row < sheet.maxRows; row++) {
      final lrn = _cell(sheet, row, Sf1ColumnMap.lrn);
      final lastName = _cell(sheet, row, Sf1ColumnMap.lastName);

      if (lrn == null || lastName == null || _isTotalRow(lastName)) {
        result.skippedBlankOrTotal++;
        continue;
      }

      final parsed = Student(
        lrn: lrn,
        lastName: lastName,
        firstName: _cell(sheet, row, Sf1ColumnMap.firstName) ?? '',
        middleName: _cell(sheet, row, Sf1ColumnMap.middleName),
        sex: _cell(sheet, row, Sf1ColumnMap.sex),
        birthDate: _normalizeDate(_cell(sheet, row, Sf1ColumnMap.birthDate)),
        motherTongue: _cell(sheet, row, Sf1ColumnMap.motherTongue),
        ipGroup: _cell(sheet, row, Sf1ColumnMap.ipGroup),
        religion: _cell(sheet, row, Sf1ColumnMap.religion),
        addressStreet: _cell(sheet, row, Sf1ColumnMap.addressStreet),
        barangay: _cell(sheet, row, Sf1ColumnMap.barangay),
        municipality: _cell(sheet, row, Sf1ColumnMap.municipality),
        province: _cell(sheet, row, Sf1ColumnMap.province),
        fatherName: _cell(sheet, row, Sf1ColumnMap.fatherName),
        motherMaidenName: _cell(sheet, row, Sf1ColumnMap.motherMaidenName),
        guardianName: _cell(sheet, row, Sf1ColumnMap.guardianName),
        guardianRelationship: _cell(sheet, row, Sf1ColumnMap.guardianRelationship),
        contactNumber: _cell(sheet, row, Sf1ColumnMap.contactNumber),
        learningModality: _cell(sheet, row, Sf1ColumnMap.learningModality),
        remarks: _cell(sheet, row, Sf1ColumnMap.remarks),
      );

      final existing = await studentRepo.findByLrn(lrn);

      if (existing == null) {
        final inserted = await studentRepo.insert(parsed);
        await studentRepo.enroll(studentId: inserted.id!, sectionId: section.id!, schoolYear: section.schoolYear);
        result.inserted++;
      } else {
        // Per your instruction: flag conflicts for manual review, never auto-overwrite.
        await conflictRepo.log(ImportConflict(
          lrn: lrn,
          sectionId: section.id,
          reason: 'LRN already exists (existing student id ${existing.id})',
          incomingDataJson: jsonEncode(parsed.toMap()),
          existingStudentId: existing.id,
        ));
        result.conflicts++;
        _log('conflict flagged: LRN $lrn already exists');
      }
    }

    _log('done: ${result.inserted} inserted, ${result.conflicts} conflicts, ${result.skippedBlankOrTotal} skipped');
    return result;
  }
}