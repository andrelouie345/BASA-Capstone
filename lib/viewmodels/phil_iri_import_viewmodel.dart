// lib/viewmodels/phil_iri_import_viewmodel.dart
//
// Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md;
// plan Task 9 = the preview, Task 10 = the import). Admin build only: an admin
// or coordinator of the school, or the superadmin, signed in (offline is
// fine: it works on the device copy, like the CRLA import).
//
// The preview writes nothing. Per section sheet: importable / empty / not in
// BASA / already imported (the one-time lock, D10). Per learner: matched by
// name within the section (workbook, D5) or by LRN (scoresheet), else "needs
// a pick". Per reading and GST one outcome: import, import flagged (re-read,
// Untitled, scaled, blank answers, levels that differ from the workbook), or
// skipped with the reason. Rulings of Task 9 (owner 2026-11-11) are in the
// import ledger; the two scale rulings: a workbook comprehension out of
// another maximum than the passage's questions, and a GST out of another
// maximum than the grade's, are converted proportionally (flagged).
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/console/logger.dart';
import '../core/data/local/sqlite_values.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/phil_iri_answer.dart';
import '../core/models/phil_iri_assessment.dart';
import '../core/models/phil_iri_collection.dart';
import '../core/models/phil_iri_gst_result.dart';
import '../core/models/phil_iri_import.dart';
import '../core/models/phil_iri_miscue.dart';
import '../core/models/phil_iri_passage.dart';
import '../core/models/phil_iri_question.dart';
import '../core/models/phil_iri_reading.dart';
import '../core/models/phil_iri_workbook_import.dart';
import '../core/models/school.dart';
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/sync_upload.dart';
import '../core/models/user_role.dart';
import '../core/repositories/phil_iri_assessment_repository.dart';
import '../core/repositories/phil_iri_collection_repository.dart';
import '../core/repositories/phil_iri_gst_repository.dart';
import '../core/repositories/phil_iri_import_writer.dart';
import '../core/repositories/phil_iri_passage_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/sync_upload_local_repository.dart';
import '../core/services/auth_messages.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_import_headers.dart';
import '../core/services/phil_iri_import_matching.dart';
import '../core/services/phil_iri_results.dart';
import '../core/services/phil_iri_scoresheet_reader.dart';
import '../core/services/phil_iri_scoresheet_template.dart';
import '../core/services/phil_iri_workbook_reader.dart';
import '../core/services/sync_upload_rules.dart';
import '../core/services/table_reader.dart';
import '../core/services/xlsx_cells.dart';
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
import 'sync_viewmodel.dart';
import 'viewmodel_exception.dart';

enum PhilIriImportOutcome { import, importFlagged, skipped }

/// One entry of the preview: a reading, a GST, or a round the reader already
/// left out ([skip]). [student] = the matched learner; [candidates] when the
/// learner needs a pick. [notes] = the flags (importFlagged) or the skip
/// reason (skipped). [session] / [gstResult] = what the import would write.
class PhilIriImportRow {
  final PhilIriImportReading? reading;
  final PhilIriImportGst? gst;
  final PhilIriImportSkip? skip;
  final Student? student;
  final List<Student> candidates;
  final PhilIriPassage? passage;
  final PhilIriImportOutcome outcome;
  final List<String> notes;
  final String? basaProfile;
  final int? basaAdjustedLevel;
  final PhilIriImportedSession? session;
  final PhilIriGstResult? gstResult;

  const PhilIriImportRow({
    this.reading,
    this.gst,
    this.skip,
    this.student,
    this.candidates = const [],
    this.passage,
    required this.outcome,
    this.notes = const [],
    this.basaProfile,
    this.basaAdjustedLevel,
    this.session,
    this.gstResult,
  });

  PhilIriImportRef get ref => reading?.ref ?? gst?.ref ?? skip!.ref;
  PhilIriLearnerKey get learner => reading?.learner ?? gst?.learner ?? skip!.learner;
  PhilIriRound? get round => reading?.round ?? skip?.round;

  /// The learner's row in the file ("sheet 03, row 17"): the key of
  /// [PhilIriImportChoices.picks].
  String get learnerRef => PhilIriImportRef(sheet: ref.sheet, row: ref.row).toString();

  PhilIriImportRow _with({
    PhilIriImportOutcome? outcome,
    List<String>? notes,
    String? basaProfile,
    int? basaAdjustedLevel,
  }) =>
      PhilIriImportRow(
        reading: reading,
        gst: gst,
        skip: skip,
        student: student,
        candidates: candidates,
        passage: passage,
        outcome: outcome ?? this.outcome,
        notes: notes ?? this.notes,
        basaProfile: basaProfile ?? this.basaProfile,
        basaAdjustedLevel: basaAdjustedLevel ?? this.basaAdjustedLevel,
        session: session,
        gstResult: gstResult,
      );
}

class PhilIriImportSectionPreview {
  static const importable = 'importable';
  static const empty = 'empty';
  static const notInBasa = 'not in BASA';
  static const alreadyImported = 'already imported';

  final PhilIriImportSectionRef ref;
  final Section? section;
  final String status;
  /// Why the section is not in BASA, or the duplicate-sheets note.
  final List<String> notes;
  final List<PhilIriImportRow> rows;
  /// Bytes the importable rows would add to the next upload (D19).
  final int uploadBytes;

  const PhilIriImportSectionPreview({
    required this.ref,
    this.section,
    required this.status,
    this.notes = const [],
    this.rows = const [],
    this.uploadBytes = 0,
  });

  int count(PhilIriImportOutcome o) => rows.where((r) => r.outcome == o).length;
}

class PhilIriImportPreview {
  final PhilIriImportPlan plan;
  final List<PhilIriHeaderIssue> headerIssues;
  final List<PhilIriImportSectionPreview> sections;
  /// Workbook: the date each round's readings would get (the calendar's
  /// window start, or the choice); null = not known, a date must be given.
  final Map<PhilIriRound, String?> proposedDates;
  /// Bytes of the device's work not uploaded yet.
  final int unsentBytes;
  final String oneTimeWarning;
  final String fingerprint;

  const PhilIriImportPreview({
    required this.plan,
    this.headerIssues = const [],
    this.sections = const [],
    this.proposedDates = const {},
    this.unsentBytes = 0,
    required this.oneTimeWarning,
    required this.fingerprint,
  });
}

/// The coordinator's choices: ticked sheets, learner picks (the learner's
/// row "sheet 03, row 17" -> student id) and round dates (YYYY-MM-DD).
class PhilIriImportChoices {
  final Set<String> sheets;
  final Map<String, int> picks;
  final Map<PhilIriRound, String> dates;

  const PhilIriImportChoices({this.sheets = const {}, this.picks = const {}, this.dates = const {}});
}

/// What an import wrote. [failed]: the learner's row ("sheet 03, row 17";
/// scoresheet "LRN ...") -> why the device refused it (the others were
/// written). [nothingToImport]: ticked sheets with only skipped rows (not
/// locked).
class PhilIriImportResult {
  final PhilIriImportPreview preview;
  final List<int> sessionIds;
  final List<int> gstIds;
  final Map<String, String> failed;
  final List<String> nothingToImport;

  const PhilIriImportResult({
    required this.preview,
    this.sessionIds = const [],
    this.gstIds = const [],
    this.failed = const {},
    this.nothingToImport = const [],
  });
}

class PhilIriImportViewModel {
  static const staleMessage = 'The data changed since the preview. Preview again before importing.';
  static const oneTimeWarningText =
      "This makes BASA the record for this section's school year. You can't import this section's workbook again.";
  static const forbiddenMessage = 'Forbidden: only an admin or coordinator imports Phil-IRI results.';

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final PhilIriViewModel _philIri;
  final RoundCalendarViewModel _calendar;
  final PhilIriAssessmentRepository _sessions;
  final PhilIriGstRepository _gst;
  final PhilIriPassageRepository _passages;
  final PhilIriCollectionRepository _collections;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final StudentRepository _students;
  final PhilIriImportWriter _writer;
  final SyncUploadLocalRepository _uploadLocal;
  final String _headersDir;
  final int _maxBytes;

  PhilIriImportViewModel({
    required AuthViewModel auth,
    required PhilIriViewModel philIri,
    required RoundCalendarViewModel calendar,
    required PhilIriAssessmentRepository sessions,
    required PhilIriGstRepository gst,
    required PhilIriPassageRepository passages,
    required PhilIriCollectionRepository collections,
    required SchoolRepository schools,
    required SectionRepository sections,
    required StudentRepository students,
    required PhilIriImportWriter writer,
    required SyncUploadLocalRepository uploadLocal,
    required String headersDir,
    int? maxBytes,
    Logger? logger,
  })  : _maxBytes = maxBytes ?? maxPackageBytes,
        _auth = auth,
        _philIri = philIri,
        _calendar = calendar,
        _sessions = sessions,
        _gst = gst,
        _passages = passages,
        _collections = collections,
        _schools = schools,
        _sections = sections,
        _students = students,
        _writer = writer,
        _uploadLocal = uploadLocal,
        _headersDir = headersDir,
        _log = ScopedLogger(logger, 'PhilIriImportViewModel');

  // ---- access ----

  void _requireImporter() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException(forbiddenMessage);
    }
  }

  Future<PhilIriImportHeaders> _headers() => PhilIriImportHeaders.load(_headersDir);

  // ---- preview ----

  /// The workbook preview (nothing written). [choices]: learner picks and
  /// round dates are applied; the ticked sheets only matter to the import.
  Future<PhilIriImportPreview> previewWorkbook(List<int> bytes,
      {PhilIriImportChoices choices = const PhilIriImportChoices()}) async {
    _requireImporter();
    _log('previewWorkbook(${bytes.length} bytes, picks: ${choices.picks.length}, dates: ${choices.dates.length})');
    final PhilIriImportPlan plan;
    try {
      plan = readPhilIriWorkbook(bytes, await _headers());
    } on FormatException catch (e) {
      throw ViewModelException('This is not a readable .xlsx workbook: ${e.message}');
    } on XlsxException catch (e) {
      throw ViewModelException('This is not a readable .xlsx workbook: ${e.message}');
    }
    if (plan.headerIssues.isNotEmpty) return _headerStop(plan);

    final run = _Run(this, plan, choices);
    final resolved = <(PhilIriImportSectionRef, Section?, String, List<String>)>[];
    for (final ref in plan.sections) {
      resolved.add(await _resolveSection(ref));
    }

    // Two sheets naming one section (Task 6 ruling): both noted; the import
    // refuses when both are ticked.
    final bySection = <int, List<String>>{};
    for (final (ref, section, status, _) in resolved) {
      if (section != null && status != PhilIriImportSectionPreview.empty) {
        (bySection[section.id!] ??= []).add(ref.sheet);
      }
    }

    // Round dates: the calendar of the first importable section's school.
    final first = resolved.where((r) => r.$3 == PhilIriImportSectionPreview.importable).firstOrNull?.$2;
    final proposed = <PhilIriRound, String?>{for (final r in PhilIriRound.values) r: null};
    if (first != null) {
      for (final e in await _calendar.effectiveCalendar(first.schoolId, first.schoolYear)) {
        final w = e.window;
        if (w.instrument != CalendarInstrument.philIri || w.skipped || w.opensOn == null) continue;
        final round = PhilIriRound.values.where((r) => r.name == w.round).firstOrNull;
        if (round != null) proposed[round] = w.opensOn;
      }
    }
    final dates = {for (final r in PhilIriRound.values) r: choices.dates[r] ?? proposed[r]};
    run.dates = dates;

    final sections = <PhilIriImportSectionPreview>[];
    for (final (ref, section, status, notes) in resolved) {
      final allNotes = [...notes];
      final sheets = section == null ? null : bySection[section.id!];
      if (sheets != null && sheets.length > 1) {
        allNotes.add('sheets ${sheets.join(' and ')} both name section ${section!.sectionName}: tick one');
      }
      if (status != PhilIriImportSectionPreview.importable) {
        sections.add(PhilIriImportSectionPreview(ref: ref, section: section, status: status, notes: allNotes));
        continue;
      }
      final rows = await run.sectionRows(section!, ref.sheet, PhilIriImportSource.workbook);
      sections.add(PhilIriImportSectionPreview(
        ref: ref,
        section: section,
        status: status,
        notes: allNotes,
        rows: rows,
        uploadBytes: _uploadBytes(rows, lock: section),
      ));
    }
    return _finish(plan, sections, {for (final r in PhilIriRound.values) r: dates[r]}, run);
  }

  /// The scoresheet preview for one section (nothing written). Rows carry
  /// their own dates; learners by LRN among the section's learners.
  Future<PhilIriImportPreview> previewScoresheet(int sectionId, List<int> bytes, String fileName) async {
    _requireImporter();
    _log('previewScoresheet(section: $sectionId, file: $fileName)');
    final (section, grade) = await _ownSection(sectionId);
    final PhilIriImportPlan plan;
    try {
      plan = readPhilIriScoresheet(bytes, fileName, await _headers());
    } on TableReadException catch (e) {
      throw ViewModelException(e.message);
    } on FormatException catch (e) {
      throw ViewModelException('This file cannot be read: ${e.message}');
    }
    if (plan.headerIssues.isNotEmpty) return _headerStop(plan);

    final run = _Run(this, plan, const PhilIriImportChoices());
    final sheet = [...plan.gst.map((g) => g.ref.sheet), ...plan.readings.map((r) => r.ref.sheet), ...plan.skipped.map((s) => s.ref.sheet)]
            .firstOrNull ??
        fileName;
    final rows = await run.sectionRows(section, null, PhilIriImportSource.scoresheet);
    final ref = PhilIriImportSectionRef(
      sheet: sheet,
      schoolYear: section.schoolYear,
      grade: grade,
      sectionName: section.sectionName,
      empty: rows.isEmpty,
    );
    final preview = PhilIriImportSectionPreview(
      ref: ref,
      section: section,
      status: PhilIriImportSectionPreview.importable,
      rows: rows,
      uploadBytes: _uploadBytes(rows),
    );
    return _finish(plan, [preview], const {}, run);
  }

  /// The section [sectionId] of the signed-in user's school (any school:
  /// the superadmin), Grade 4-10; with its grade.
  Future<(Section, int)> _ownSection(int sectionId) async {
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    final me = _auth.currentUser!;
    if (me.schoolId != null && me.schoolId != section.schoolId) {
      throw const ViewModelException('Forbidden: that section is in another school.');
    }
    final grade = int.tryParse(section.gradeLevel);
    if (grade == null || grade < 4 || grade > 10) {
      throw ViewModelException('Phil-IRI is for Grade 4-10 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }
    return (section, grade);
  }

  /// The grade-leveled passages a school's sections read (the pool and the
  /// school's own collections) and which of them are active.
  Future<(List<PhilIriPassage>, Set<int>)> _schoolPassages(int schoolId) async {
    final list = <PhilIriPassage>[];
    final active = <int>{};
    for (final PhilIriCollection c in await _collections.getAll()) {
      if (!c.isGradeLeveled || (c.schoolId != null && c.schoolId != schoolId)) continue;
      for (final p in await _passages.getByCollection(c.id!)) {
        list.add(p);
        if (p.isActive && c.isActive) active.add(p.id!);
      }
    }
    return (list, active);
  }

  PhilIriImportPreview _headerStop(PhilIriImportPlan plan) => PhilIriImportPreview(
        plan: plan,
        headerIssues: plan.headerIssues,
        oneTimeWarning: oneTimeWarningText,
        fingerprint: _hash(['headers', for (final i in plan.headerIssues) '${i.field}|${i.block}']),
      );

  Future<PhilIriImportPreview> _finish(PhilIriImportPlan plan, List<PhilIriImportSectionPreview> sections,
      Map<PhilIriRound, String?> dates, _Run run) async {
    final package = await _uploadLocal.buildPackage(release: SyncViewModel.release);
    final unsent = package.isEmpty ? 0 : utf8.encode(jsonEncode(package.toJson())).length;
    final parts = <String>[
      plan.source.value,
      for (final e in dates.entries) '${e.key.name}=${e.value}',
      for (final s in sections) ...[
        's|${s.ref.sheet}|${s.section?.id}|${s.status}|${s.notes.join(';')}',
        for (final r in s.rows)
          'r|${r.ref}|${r.round?.name}|${r.outcome.name}|${r.student?.id}|${r.passage?.id}|${r.notes.join(';')}'
              '|${r.reading?.seconds}|${r.reading?.wordsRead}|${r.reading?.correctCount}|${r.reading?.answers?.join(',')}'
              '|${r.reading?.miscues.entries.map((e) => '${e.key.name}${e.value}').join(',')}|${r.reading?.selfCorrected}'
              '|${r.gst?.score}|${r.reading?.date ?? r.gst?.date}',
      ],
      ...run.existing,
    ];
    return PhilIriImportPreview(
      plan: plan,
      sections: sections,
      proposedDates: dates,
      unsentBytes: unsent,
      oneTimeWarning: oneTimeWarningText,
      fingerprint: _hash(parts),
    );
  }

  static String _hash(List<String> parts) => sha256.convert(utf8.encode(parts.join('\n'))).toString();

  // ---- sections ----

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<(PhilIriImportSectionRef, Section?, String, List<String>)> _resolveSection(PhilIriImportSectionRef ref) async {
    const notIn = PhilIriImportSectionPreview.notInBasa;
    if (ref.empty) return (ref, null, PhilIriImportSectionPreview.empty, const <String>[]);
    final me = _auth.currentUser!;
    School? school;
    if (ref.depedSchoolId != null) {
      school = await _schools.getByCode(ref.depedSchoolId!);
      if (school == null) return (ref, null, notIn, ['school ${ref.depedSchoolId} is not in BASA']);
    } else if (me.schoolId != null) {
      school = await _schools.getById(me.schoolId!);
    }
    if (school == null) return (ref, null, notIn, const ['no school ID on the sheet']);
    if (me.schoolId != null && me.schoolId != school.id) {
      return (ref, null, notIn, const ["another school's section: only its own coordinator or the superadmin imports it"]);
    }
    final missing = [
      if (ref.schoolYear == null) 'school year',
      if (ref.grade == null) 'grade',
      if (ref.sectionName == null || ref.sectionName!.isEmpty) 'section name',
    ];
    if (missing.isNotEmpty) return (ref, null, notIn, ['the sheet has no ${missing.join(', ')}']);
    final year = normalizeSchoolYear(ref.schoolYear!);
    final want = _norm(ref.sectionName!);
    final section = (await _sections.getAll())
        .where((s) =>
            s.schoolId == school!.id &&
            s.schoolYear == year &&
            s.gradeLevel == '${ref.grade}' &&
            _norm(s.sectionName) == want)
        .firstOrNull;
    if (section == null) {
      return (
        ref,
        null,
        notIn,
        ['create section Grade ${ref.grade} ${ref.sectionName} ($year) in ${school.schoolName} first (SF1 import)'],
      );
    }
    if (await _writer.isLocked(section.id!, section.schoolYear)) {
      return (ref, section, PhilIriImportSectionPreview.alreadyImported, const <String>[]);
    }
    return (ref, section, PhilIriImportSectionPreview.importable, const <String>[]);
  }

  // ---- upload size (D19) ----

  /// The JSON bytes the importable rows (and [lock]'s row) would add to the
  /// next upload: the same server rows and follow-ups the package builds.
  int _uploadBytes(List<PhilIriImportRow> rows, {Section? lock}) {
    var bytes = 0;
    var id = -1;
    void add(String table, Map<String, Object?> local) {
      final key = id--;
      final row = toServerRow(table, toSqliteRow({...local, 'id': key}), keyColumn: 'id', insert: true);
      final records = [
        SyncRecord(table: table, op: 'insert', keyColumn: 'id', key: key, row: row),
        for (final f in followUpsForNew(table, row)) SyncRecord(table: table, op: 'update', keyColumn: 'id', key: key, row: f),
      ];
      for (final r in records) {
        bytes += utf8.encode(jsonEncode(r.toJson())).length + 1; // + the comma
      }
    }

    // Columns the device database fills in: created_at on every row (SQLite's
    // "YYYY-MM-DD HH:MM:SS"), attempt_no (sessions, GST), imported_at (lock).
    final now = DateTime.now().toUtc().toIso8601String();
    const stamp = '2000-01-01 00:00:00';
    for (final r in rows.where((r) => r.outcome != PhilIriImportOutcome.skipped)) {
      final g = r.gstResult;
      if (g != null) add('phil_iri_gst_results', {...g.toMap(), 'attempt_no': 1, 'created_at': stamp});
      final s = r.session;
      if (s == null) continue;
      final sessionId = id;
      add('phil_iri_assessments', {
        ...s.assessment.toMap(),
        'attempt_no': 1,
        'status': PhilIriStatus.completed.value,
        'completed_at': now,
        'created_at': stamp,
      });
      final reading = s.reading.toMap();
      for (final c in PhilIriReading.resultColumns) {
        reading.remove(c);
      }
      final readingId = id;
      add('phil_iri_readings', {...reading, 'assessment_id': sessionId, 'created_at': stamp});
      for (final m in s.miscues) {
        add('phil_iri_miscues', {...m.toMap(), 'reading_id': readingId, 'created_at': stamp});
      }
      for (final a in s.answers) {
        add('phil_iri_answers', {...a.toMap(), 'reading_id': readingId, 'created_at': stamp});
      }
    }
    if (lock != null && rows.any((r) => r.outcome != PhilIriImportOutcome.skipped)) {
      add('phil_iri_workbook_imports', {
        ...PhilIriWorkbookImport(schoolId: lock.schoolId, sectionId: lock.id!, schoolYear: lock.schoolYear).toMap(),
        'imported_at': stamp,
      });
    }
    return bytes;
  }

  // ---- import (Task 10) ----

  /// Imports the ticked sheets of a workbook. [fingerprint] = the one of
  /// the preview the coordinator saw (with the same [choices]); the preview
  /// is rebuilt and the import refused when anything changed. One device
  /// transaction per learner; each section's lock with its last learner.
  /// No sync: the coordinator uploads afterwards (D18).
  Future<PhilIriImportResult> importWorkbook(List<int> bytes, PhilIriImportChoices choices,
      {required String fingerprint}) async {
    _requireImporter();
    _log('importWorkbook(${bytes.length} bytes, sheets: ${(choices.sheets.toList()..sort()).join(', ')})');
    if (choices.sheets.isEmpty) throw const ViewModelException('Tick at least one section.');
    final preview = await previewWorkbook(bytes, choices: choices);
    if (preview.headerIssues.isNotEmpty) {
      throw const ViewModelException('The workbook has header issues: fix them in the Headers step and preview again.');
    }
    for (final sheet in choices.sheets.toList()..sort()) {
      final s = preview.sections.where((x) => x.ref.sheet == sheet).firstOrNull;
      if (s == null) throw ViewModelException('There is no section sheet $sheet in this workbook.');
      if (s.status != PhilIriImportSectionPreview.importable) {
        throw ViewModelException("Sheet $sheet can't be imported: ${s.status}.");
      }
    }
    // In workbook order (the upload-size count follows it).
    final ticked = preview.sections.where((s) => choices.sheets.contains(s.ref.sheet)).toList();
    final bySection = <int, List<String>>{};
    for (final s in ticked) {
      (bySection[s.section!.id!] ??= []).add(s.ref.sheet);
    }
    for (final sheets in bySection.values.where((l) => l.length > 1)) {
      final s = ticked.firstWhere((x) => x.ref.sheet == sheets.first);
      throw ViewModelException('sheets ${sheets.join(' and ')} both name section ${s.section!.sectionName}: tick one');
    }
    if (preview.fingerprint != fingerprint) throw const ViewModelException(staleMessage);

    // A date for every round that has something to import (GST: BOSY's).
    for (final round in PhilIriRound.values) {
      final needed = ticked.any((s) => s.rows.any((r) =>
          r.outcome != PhilIriImportOutcome.skipped &&
          ((r.session != null && r.reading!.round == round) || (r.gstResult != null && round == PhilIriRound.bosy))));
      if (!needed) continue;
      final date = preview.proposedDates[round];
      if (date == null || date.trim().isEmpty) throw ViewModelException('Give a date for ${round.label}.');
      if (!_isDate(date)) throw ViewModelException('${round.label}: $date is not a date (YYYY-MM-DD).');
    }
    _checkUploadSize(ticked, preview.unsentBytes);
    return _write(preview, ticked, lock: true);
  }

  /// Imports a filled scoresheet file of one section (repeatable: what BASA
  /// has is skipped, never overwritten; no lock). [fingerprint] as in
  /// [importWorkbook].
  Future<PhilIriImportResult> importScoresheet(int sectionId, List<int> bytes, String fileName,
      {required String fingerprint}) async {
    _requireImporter();
    _log('importScoresheet(section: $sectionId, file: $fileName)');
    final preview = await previewScoresheet(sectionId, bytes, fileName);
    if (preview.headerIssues.isNotEmpty) {
      throw const ViewModelException('The file has header issues: fix them in the Headers step and preview again.');
    }
    if (preview.fingerprint != fingerprint) throw const ViewModelException(staleMessage);
    _checkUploadSize(preview.sections, preview.unsentBytes);
    return _write(preview, preview.sections, lock: false);
  }

  static bool _isDate(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
    final d = DateTime.tryParse(s);
    return d != null && d.toIso8601String().substring(0, 10) == s;
  }

  static String _sectionLabel(PhilIriImportSectionPreview s) => '${s.ref.sheet} ${s.section!.sectionName}';

  /// D19: the sections (in order) and the device's unsent work must fit one
  /// upload; else says how many fit.
  void _checkUploadSize(List<PhilIriImportSectionPreview> sections, int unsent) {
    for (final s in sections) {
      if (s.uploadBytes > _maxBytes) {
        throw ViewModelException('Too much for one upload: sheet ${_sectionLabel(s)} alone is '
            '${(s.uploadBytes / 1024).ceil()} KB, more than one upload (${(_maxBytes / 1024).floor()} KB).');
      }
    }
    var total = unsent;
    final fit = <PhilIriImportSectionPreview>[];
    for (final s in sections) {
      if (total + s.uploadBytes > _maxBytes) break;
      total += s.uploadBytes;
      fit.add(s);
    }
    if (fit.length == sections.length) return;
    if (fit.isEmpty) {
      throw const ViewModelException('Too much for one upload: none of the ticked sections fit with the work '
          'not uploaded yet. Upload first.');
    }
    throw ViewModelException('Too much for one upload: ${fit.length} of the ticked sections fit '
        '(${fit.map(_sectionLabel).join(', ')}). Import them, upload, then import the rest.');
  }

  static String _reason(Object e) => e is ViewModelException ? e.message : '$e';

  /// One writeLearner per learner; a refused learner is reported and the
  /// others go on. [lock]: each section's lock goes with its last learner,
  /// alone when that one is refused but another was written.
  Future<PhilIriImportResult> _write(PhilIriImportPreview preview, List<PhilIriImportSectionPreview> sections,
      {required bool lock}) async {
    final sessionIds = <int>[];
    final gstIds = <int>[];
    final failed = <String, String>{};
    final nothing = <String>[];
    for (final s in sections) {
      final section = s.section!;
      final byStudent = <int, List<PhilIriImportRow>>{};
      for (final r in s.rows.where((r) => r.outcome != PhilIriImportOutcome.skipped)) {
        (byStudent[r.student!.id!] ??= []).add(r);
      }
      if (byStudent.isEmpty) {
        nothing.add(s.ref.sheet);
        continue;
      }
      final theLock = lock
          ? PhilIriWorkbookImport(schoolId: section.schoolId, sectionId: section.id!, schoolYear: section.schoolYear)
          : null;
      final students = byStudent.keys.toList();
      var written = 0;
      var locked = false;
      for (final id in students) {
        final rows = byStudent[id]!;
        final last = id == students.last;
        final ref = lock ? rows.first.learnerRef : 'LRN ${rows.first.learner.lrn}';
        try {
          final w = await _writer.writeLearner(
            sessions: [for (final r in rows) if (r.session != null) r.session!],
            gst: rows.where((r) => r.gstResult != null).firstOrNull?.gstResult,
            lock: last ? theLock : null,
          );
          sessionIds.addAll(w.sessions);
          if (w.gst != null) gstIds.add(w.gst!);
          written++;
          if (last && theLock != null) locked = true;
        } catch (e) {
          failed[ref] = _reason(e);
          _log('import: $ref refused: ${_reason(e)}');
        }
      }
      if (theLock != null && !locked && written > 0) {
        try {
          await _writer.writeLearner(sessions: const [], lock: theLock);
        } catch (e) {
          failed['sheet ${s.ref.sheet} (the one-time lock)'] = _reason(e);
        }
      }
    }
    _log('import: ${sessionIds.length} sessions, ${gstIds.length} GST, ${failed.length} refused');
    return PhilIriImportResult(
      preview: preview,
      sessionIds: sessionIds,
      gstIds: gstIds,
      failed: failed,
      nothingToImport: nothing,
    );
  }

  // ---- scoresheet template ----

  /// The section's scoresheet file (.xlsx): its learners (by last, then
  /// first name) and the grade's active passages in the lists.
  Future<List<int>> scoresheetTemplate(int sectionId) async {
    _requireImporter();
    _log('scoresheetTemplate(section: $sectionId)');
    final (section, _) = await _ownSection(sectionId);
    String k(String? s) => (s ?? '').trim().toLowerCase();
    final learners = [...await _students.getBySection(section.id!)]
      ..sort((a, b) {
        final c = k(a.lastName).compareTo(k(b.lastName));
        return c != 0 ? c : k(a.firstName).compareTo(k(b.firstName));
      });
    final (passages, active) = await _schoolPassages(section.schoolId);
    return buildPhilIriScoresheetTemplate(
      section: section,
      learners: learners,
      passages: passages.where((p) => active.contains(p.id)).toList(),
      headers: await _headers(),
    );
  }

  // ---- header labels (device-saved, D14) ----

  /// Every header field and the label the readers look for on this device.
  Future<Map<String, String>> headerLabels() async {
    _requireImporter();
    final h = await _headers();
    return {for (final f in PhilIriImportHeaders.defaults.keys) f: h.label(f)};
  }

  /// Changes one header label; returns the error, or null when saved.
  Future<String?> setHeader(String field, String label) async {
    _requireImporter();
    _log('setHeader($field)');
    return (await _headers()).set(field, label);
  }

  /// Back to BASA's default labels.
  Future<void> resetHeaders() async {
    _requireImporter();
    _log('resetHeaders()');
    await (await _headers()).reset();
  }

  // ---- header step ----

  /// The first [count] values under the header [label] in [field]'s column
  /// (workbook: every round block of every section sheet that has it;
  /// scoresheet: the first sheet), so a coordinator can check a header pick.
  /// Names are never shown.
  Future<List<String>> headerSamples(List<int> bytes, String field, String label, {int count = 5}) async {
    _requireImporter();
    if (!PhilIriImportHeaders.defaults.containsKey(field)) throw ViewModelException('Unknown header field "$field"');
    final want = normalizeHeader(label);
    if (field == 'wb.name' || (field.startsWith('ss.') && want == normalizeHeader('Learner'))) {
      throw const ViewModelException('Names are not shown here.');
    }
    final out = <String>[];
    if (field.startsWith('ss.')) {
      final (headers, rows) = readTable(bytes, 'file.xlsx');
      final i = headers.indexWhere((h) => normalizeHeader(h) == want);
      if (i < 0) return out;
      for (final r in rows) {
        final v = r.get([headers[i]]);
        if (v != null && v.trim().isNotEmpty) out.add(v.trim());
        if (out.length >= count) break;
      }
      return out;
    }
    final wb = XlsxWorkbook.decode(bytes);
    for (final sheet in wb.sheetNames) {
      if (sheet.trim().toLowerCase() == 'sample') continue;
      final cells = wb.readSheet(sheet);
      final cols = <int>{};
      for (final e in cells.entries) {
        final (col, row) = splitRef(e.key);
        if (row >= 9 && row <= 12 && e.value is String && normalizeHeader(e.value as String) == want) cols.add(col);
      }
      for (final col in cols.toList()..sort()) {
        for (var row = 13; row < 400 && out.length < count; row++) {
          final v = cells['${columnLetters(col)}$row'];
          if (v != null && '$v'.trim().isNotEmpty) out.add('$v'.trim());
        }
        if (out.length >= count) return out;
      }
    }
    return out;
  }
}

/// One preview run: caches content and thresholds, keeps the existing
/// sessions it saw (for the fingerprint).
class _Run {
  final PhilIriImportViewModel vm;
  final PhilIriImportPlan plan;
  final PhilIriImportChoices choices;
  Map<PhilIriRound, String?> dates = const {};
  final existing = <String>[];

  _Run(this.vm, this.plan, this.choices);

  final _passagesBySchool = <int, List<PhilIriPassage>>{};
  final _activePassages = <int>{};
  final _questions = <int, List<PhilIriQuestion>>{};

  Future<List<PhilIriPassage>> _passagesFor(int schoolId) async {
    final cached = _passagesBySchool[schoolId];
    if (cached != null) return cached;
    final (list, active) = await vm._schoolPassages(schoolId);
    _activePassages.addAll(active);
    return _passagesBySchool[schoolId] = list;
  }

  Future<List<PhilIriQuestion>> _questionsOf(int passageId) async =>
      _questions[passageId] ??= await vm._passages.getQuestions(passageId);

  /// Every row of one section: [sheet] = the workbook sheet (null: the
  /// whole scoresheet plan is this section's).
  Future<List<PhilIriImportRow>> sectionRows(Section section, String? sheet, PhilIriImportSource source) async {
    final grade = int.parse(section.gradeLevel);
    final t = await vm._philIri.effectiveThresholds(section.schoolId);
    final passages = await _passagesFor(section.schoolId);
    final learners = await vm._students.getBySection(section.id!);
    bool mine(PhilIriImportRef r) => sheet == null || r.sheet == sheet;
    final gsts = plan.gst.where((g) => mine(g.ref)).toList();
    final readings = plan.readings.where((r) => mine(r.ref)).toList();
    final skips = plan.skipped.where((s) => mine(s.ref)).toList();

    // ---- learners ----
    final byLrn = {for (final s in learners) s.lrn.trim(): s};
    final match = <String, Student?>{}; // learner key -> student
    final candidates = <String, List<Student>>{};
    final reasons = <String, String>{};
    String keyOf(PhilIriImportRef ref, PhilIriLearnerKey k) =>
        source == PhilIriImportSource.scoresheet ? 'lrn ${k.lrn}' : PhilIriImportRef(sheet: ref.sheet, row: ref.row).toString();
    final keys = <String, PhilIriLearnerKey>{};
    for (final (ref, k) in [
      for (final g in gsts) (g.ref, g.learner),
      for (final r in readings) (r.ref, r.learner),
      for (final s in skips) (s.ref, s.learner),
    ]) {
      keys.putIfAbsent(keyOf(ref, k), () => k);
    }
    for (final e in keys.entries) {
      final k = e.value;
      if (source == PhilIriImportSource.scoresheet) {
        final s = k.lrn == null ? null : byLrn[k.lrn!.trim()];
        match[e.key] = s;
        if (s == null) reasons[e.key] = 'LRN ${k.lrn} is not an active learner of this section';
        continue;
      }
      final pick = choices.picks[e.key];
      if (pick != null) {
        final s = learners.where((l) => l.id == pick).firstOrNull;
        match[e.key] = s;
        if (s == null) {
          reasons[e.key] = 'the picked learner ($pick) is not in this section';
          candidates[e.key] = learners;
        }
        continue;
      }
      final named = philIriNameCandidates(k, learners);
      final sexOk = named.length == 1 &&
          (named.single.sex == null ||
              k.sex == null ||
              named.single.sex!.trim().toUpperCase().startsWith(k.sex!.toUpperCase()));
      if (sexOk) {
        match[e.key] = named.single;
      } else {
        match[e.key] = null;
        reasons[e.key] = 'needs a pick';
        candidates[e.key] = [...named, ...learners.where((l) => !named.contains(l))];
      }
    }
    // Two file learners on one BASA learner: both need a pick (workbook).
    if (source == PhilIriImportSource.workbook) {
      final byStudent = <int, List<String>>{};
      match.forEach((key, s) {
        if (s != null) (byStudent[s.id!] ??= []).add(key);
      });
      for (final list in byStudent.values.where((l) => l.length > 1)) {
        for (final key in list) {
          match[key] = null;
          reasons[key] = 'needs a pick: matched twice (${list.join('; ')})';
          candidates[key] = learners;
        }
      }
    }

    // ---- what BASA already has ----
    final roundState = <int, Map<PhilIriRound, PhilIriStatus>>{};
    final readPassages = <int, Map<int, PhilIriRound>>{};
    final hasGst = <int>{};
    for (final s in match.values.whereType<Student>().toSet()) {
      final states = roundState[s.id!] = {};
      final read = readPassages[s.id!] = {};
      for (final a in await vm._sessions.getByStudent(s.id!, schoolYear: section.schoolYear)) {
        existing.add('a|${a.id}|${a.status.value}');
        final prev = states[a.round];
        if (prev == null || prev != PhilIriStatus.inProgress) states[a.round] = a.status;
        for (final r in await vm._sessions.getReadings(a.id!)) {
          if (r.passageId != null) read[r.passageId!] = a.round;
        }
      }
      final g = await vm._gst.getByStudent(s.id!, schoolYear: section.schoolYear);
      for (final x in g) {
        existing.add('g|${x.id}');
      }
      if (g.isNotEmpty) hasGst.add(s.id!);
    }

    final me = vm._auth.currentUser!;
    final gradeMax = grade >= 7 ? 40 : 20;
    final rows = <PhilIriImportRow>[];
    final gstFraction = <int, double>{};

    // ---- GST ----
    for (final g in gsts) {
      final key = keyOf(g.ref, g.learner);
      final s = match[key];
      if (s == null) {
        rows.add(PhilIriImportRow(
            gst: g, candidates: candidates[key] ?? const [], outcome: PhilIriImportOutcome.skipped, notes: [reasons[key]!]));
        continue;
      }
      PhilIriImportRow skip(String why) =>
          PhilIriImportRow(gst: g, student: s, outcome: PhilIriImportOutcome.skipped, notes: [why]);
      if (hasGst.contains(s.id)) {
        rows.add(skip('GST already recorded this school year'));
        continue;
      }
      final fileMax = g.max;
      if (fileMax != null && g.score > fileMax) {
        rows.add(skip('${g.ref}: GST ${g.score} is more than the maximum $fileMax (unreadable)'));
        continue;
      }
      if (fileMax == null && g.score > gradeMax) {
        rows.add(skip('${g.ref}: GST ${g.score} is more than $gradeMax, the Grade $grade maximum (unreadable)'));
        continue;
      }
      final notes = <String>[];
      var score = g.score;
      if (fileMax != null && fileMax != gradeMax) {
        if (fileMax <= 0) {
          rows.add(skip('${g.ref}: the GST maximum $fileMax is unreadable'));
          continue;
        }
        score = philIriScaleCount(g.score, fileMax, gradeMax);
        notes.add('GST ${g.score} of $fileMax scaled to $score of $gradeMax');
      }
      final date = source == PhilIriImportSource.workbook ? dates[PhilIriRound.bosy] : g.date;
      final result = PhilIriGstResult(
        studentId: s.id!,
        schoolId: section.schoolId,
        sectionId: section.id!,
        schoolYear: section.schoolYear,
        maxScore: gradeMax,
        totalScore: score,
        takenAt: date ?? '',
        administeredBy: me.id,
      );
      gstFraction[s.id!] = score / gradeMax;
      rows.add(PhilIriImportRow(
        gst: g,
        student: s,
        outcome: notes.isEmpty ? PhilIriImportOutcome.import : PhilIriImportOutcome.importFlagged,
        notes: notes,
        gstResult: result,
      ));
    }

    // ---- rounds the reader left out ----
    for (final sk in skips) {
      final key = keyOf(sk.ref, sk.learner);
      rows.add(PhilIriImportRow(
          skip: sk, student: match[key], outcome: PhilIriImportOutcome.skipped, notes: [sk.reason]));
    }

    // ---- readings, in round order per learner (re-reads within the file) ----
    final ordered = [...readings]..sort((a, b) => a.round.index.compareTo(b.round.index));
    final fileRounds = <String, PhilIriImportRef>{};
    final scored = <int, Map<PhilIriRound, PhilIriPassageResult>>{};
    final readingRows = <PhilIriImportRow>[];
    for (final r in ordered) {
      final key = keyOf(r.ref, r.learner);
      final s = match[key];
      if (s == null) {
        readingRows.add(PhilIriImportRow(
            reading: r, candidates: candidates[key] ?? const [], outcome: PhilIriImportOutcome.skipped, notes: [reasons[key]!]));
        continue;
      }
      PhilIriImportRow skip(String why, {PhilIriPassage? passage}) =>
          PhilIriImportRow(reading: r, student: s, passage: passage, outcome: PhilIriImportOutcome.skipped, notes: [why]);
      final state = roundState[s.id]![r.round];
      if (state == PhilIriStatus.inProgress) {
        readingRows.add(skip('live session in progress'));
        continue;
      }
      if (state != null) {
        readingRows.add(skip('already assessed this round'));
        continue;
      }
      final roundKey = '${s.id}|${r.round.name}';
      final earlier = fileRounds[roundKey];
      if (earlier != null) {
        readingRows.add(skip('the file has another ${r.round.label} reading for this learner ($earlier)'));
        continue;
      }

      final notes = <String>[];
      PhilIriPassage? passage;
      if (r.passage == null) {
        notes.add('no passage (Untitled)');
      } else {
        passage = philIriMatchPassage(r.passage!, passages, isActive: (p) => _activePassages.contains(p.id));
        if (passage == null) {
          readingRows.add(skip('passage not in BASA: ${r.passage!.raw}'));
          continue;
        }
        if ((passage.level ?? grade) < grade) {
          readingRows.add(skip('lower-grade passage (${passage.title}, Grade ${passage.level})', passage: passage));
          continue;
        }
        if (passage.level != null && passage.level != grade) {
          readingRows.add(skip('passage of another grade (${passage.title}, Grade ${passage.level})', passage: passage));
          continue;
        }
        final readIn = readPassages[s.id]![passage.id!];
        if (readIn != null) notes.add('re-read of ${passage.title} (read in ${readIn.label})');
      }

      // Comprehension.
      int? importedCorrect, importedTotal, compCorrect, compTotal;
      final answers = <PhilIriAnswer>[];
      if (passage == null) {
        if (r.correctCount != null) {
          if (r.correctTotal == null || r.correctTotal! <= 0) {
            readingRows.add(skip('${r.ref}: comprehension without a maximum (unreadable)'));
            continue;
          }
          if (r.correctCount! > r.correctTotal!) {
            readingRows.add(skip('${r.ref}: comprehension ${r.correctCount} is more than its total ${r.correctTotal} (unreadable)'));
            continue;
          }
          importedCorrect = compCorrect = r.correctCount;
          importedTotal = compTotal = r.correctTotal;
        }
      } else {
        final questions = await _questionsOf(passage.id!);
        final q = questions.length;
        if (r.correctCount != null) {
          var correct = r.correctCount!;
          final max = r.correctTotal;
          if (max != null && max > 0 && max != q && q > 0) {
            final scaled = philIriScaleCount(correct, max, q);
            notes.add('comprehension $correct of $max scaled to $scaled of $q');
            correct = scaled;
          }
          if (correct > q) {
            readingRows.add(skip(
                '${r.ref}: comprehension ${r.correctCount} is more than the $q questions of ${passage.title} (unreadable)',
                passage: passage));
            continue;
          }
          importedCorrect = compCorrect = correct;
          compTotal = q;
        } else if (r.answers != null) {
          if (r.answers!.length > q) {
            readingRows.add(skip(
                '${r.ref}: ${r.answers!.length} answers; ${passage.title} has $q questions (unreadable)',
                passage: passage));
            continue;
          }
          var blank = 0, correct = 0;
          for (var i = 0; i < q; i++) {
            final letter = i < r.answers!.length ? r.answers![i]?.trim().toLowerCase() : null;
            final key = questions[i].answerKey.trim().toLowerCase();
            final ok = letter != null && letter == key;
            if (letter == null) blank++;
            if (ok) correct++;
            answers.add(PhilIriAnswer(readingId: 0, questionId: questions[i].id!, chosen: letter, isCorrect: ok));
          }
          if (blank > 0) notes.add('$blank answer${blank == 1 ? '' : 's'} blank (counted wrong)');
          compCorrect = correct;
          compTotal = q;
        }
      }

      // Miscues: counted rows per type; self-corrections as not-counted rows.
      final miscues = <PhilIriMiscue>[
        for (final e in r.miscues.entries)
          for (var i = 0; i < e.value; i++) PhilIriMiscue(readingId: 0, type: e.key),
        for (var i = 0; i < r.selfCorrected; i++)
          PhilIriMiscue(readingId: 0, type: PhilIriMiscueType.repetition, selfCorrected: true),
      ];

      final date = source == PhilIriImportSource.workbook ? dates[r.round] : r.date;
      final reading = PhilIriReading(
        assessmentId: 0,
        sequenceNo: 1,
        passageId: passage?.id,
        method: r.method,
        readingSeconds: r.seconds,
        wordsRead: r.wordsRead,
        importedCorrect: source == PhilIriImportSource.workbook ? importedCorrect : null,
        importedWordCount: passage == null ? r.wordCount : null,
        importedTotal: passage == null ? importedTotal : null,
      );
      final session = PhilIriImportedSession(
        assessment: PhilIriAssessment(
          studentId: s.id!,
          schoolId: section.schoolId,
          sectionId: section.id!,
          schoolYear: section.schoolYear,
          round: r.round,
          assessedAt: date ?? '',
          administeredBy: me.id,
          importSource: source,
        ),
        reading: reading,
        miscues: miscues,
        answers: answers,
      );

      try {
        (scored[s.id!] ??= {})[r.round] = philIriScorePassage(
          wordCount: passage?.wordCount ?? r.wordCount,
          method: r.method,
          readingSeconds: r.seconds,
          wordsRead: r.wordsRead,
          countedMiscues: philIriCountedMiscues(miscues),
          comprehensionCorrect: compTotal == null ? null : compCorrect,
          comprehensionTotal: compTotal,
          t: t,
          allowNoWordReading: true,
        );
      } on ArgumentError catch (e) {
        readingRows.add(skip('${r.ref}: cannot be scored (${e.message})', passage: passage));
        continue;
      }
      fileRounds[roundKey] = r.ref;
      if (passage != null) readPassages[s.id]![passage.id!] = r.round;
      readingRows.add(PhilIriImportRow(
        reading: r,
        student: s,
        passage: passage,
        outcome: PhilIriImportOutcome.import,
        notes: notes,
        session: session,
      ));
    }

    // BASA's carried result per round from the file's own GST and readings
    // (Task 9 ruling 12), compared with the workbook's saved one (D7).
    final results = <int, Map<PhilIriRound, PhilIriRoundResult>>{};
    for (final e in scored.entries) {
      final list = philIriRoundResults(learnerGrade: grade, gstScore: gstFraction[e.key], readings: e.value, t: t);
      results[e.key] = {for (final x in list) x.round: x};
    }
    for (final row in readingRows) {
      if (row.outcome == PhilIriImportOutcome.skipped || row.session == null) {
        rows.add(row);
        continue;
      }
      final res = results[row.student!.id]?[row.reading!.round];
      final notes = [...row.notes];
      final profile = res?.profile?.label;
      final level = res?.adjustedLevel;
      final wbProfile = row.reading!.workbookProfile;
      final wbLevel = row.reading!.workbookAdjustedLevel;
      final profileDiffers =
          wbProfile != null && profile != null && !philIriNameKey(wbProfile).startsWith(philIriNameKey(profile));
      final levelDiffers = wbLevel != null && level != null && wbLevel != level;
      if (profileDiffers || levelDiffers) {
        notes.add('levels differ: BASA ${profile ?? '-'} (grade ${level ?? '-'}), '
            'workbook ${wbProfile ?? '-'} (grade ${wbLevel ?? '-'})');
      }
      rows.add(row._with(
        outcome: notes.isEmpty ? PhilIriImportOutcome.import : PhilIriImportOutcome.importFlagged,
        notes: notes,
        basaProfile: profile,
        basaAdjustedLevel: level,
      ));
    }
    rows.sort((a, b) {
      final c = a.ref.sheet.compareTo(b.ref.sheet);
      if (c != 0) return c;
      final d = a.ref.row.compareTo(b.ref.row);
      if (d != 0) return d;
      return (a.round?.index ?? -1).compareTo(b.round?.index ?? -1);
    });
    return rows;
  }
}
