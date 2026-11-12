// Phil-IRI import, Task 10: the import runs (spec 2026-11-09-phil-iri-import-design,
// PhilIriImportViewModel.importWorkbook / importScoresheet / scoresheetTemplate;
// Task 10 rulings in the import ledger). A fresh device per test, signed in
// offline as the school's coordinator; made-up names.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/phil_iri_assessment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_collection_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_gst_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_import_writer_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_passage_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_upload_local_sqlite.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_gst_result.dart';
import 'package:basa_capstone/core/models/phil_iri_workbook_import.dart';
import 'package:basa_capstone/core/repositories/phil_iri_import_writer.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/phil_iri_import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';
import '../helpers/phil_iri_workbook_fixture.dart';

const _school = 9851;
const _year = '2027-2028';
const _coord = '00000000-0000-0000-0000-0000000098c5';
const _tutor = '00000000-0000-0000-0000-0000000098a5';
const _iron = 9860, _silver = 9861;
const _dust = 9951, _diving = 9952;

/// Fails the learner [failFor] (a device refusal); writes the others.
class _FailingWriter implements PhilIriImportWriter {
  final PhilIriImportWriter inner;
  int? failFor;
  final locks = <PhilIriWorkbookImport>[];
  _FailingWriter(this.inner);

  @override
  Future<PhilIriImportWritten> writeLearner(
      {required List<PhilIriImportedSession> sessions, PhilIriGstResult? gst, PhilIriWorkbookImport? lock}) async {
    final student = sessions.firstOrNull?.assessment.studentId ?? gst?.studentId;
    if (student != null && student == failFor) throw StateError('device refused learner $student');
    if (lock != null) locks.add(lock);
    return inner.writeLearner(sessions: sessions, gst: gst, lock: lock);
  }

  @override
  Future<bool> isLocked(int sectionId, String schoolYear) => inner.isLocked(sectionId, schoolYear);
}

void main() {
  late AppContext ctx;
  late Database db;
  late _FailingWriter writer;
  late PhilIriImportViewModel vm;
  late String dir;

  PhilIriImportViewModel build({int? maxBytes}) {
    final t = wireTutor(ctx, wireShared(ctx));
    return PhilIriImportViewModel(
      auth: ctx.authVm,
      philIri: t.philIriVm,
      calendar: t.calendarVm,
      sessions: PhilIriAssessmentRepositorySqlite(db),
      gst: PhilIriGstRepositorySqlite(db),
      passages: PhilIriPassageRepositorySqlite(db),
      collections: PhilIriCollectionRepositorySqlite(db),
      schools: SchoolRepositorySqlite(db),
      sections: SectionRepositorySqlite(db),
      students: StudentRepositorySqlite(db),
      writer: writer,
      uploadLocal: SyncUploadLocalSqlite(db),
      headersDir: dir,
      maxBytes: maxBytes,
      now: () => DateTime(2028, 8, 1), // after the test school year 2027-2028
    );
  }

  Future<void> signInAs(String id, String email, String role) async {
    await seedOfflineOwner(db, userId: id, email: email, role: role, schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: email, password: 'test-pw'), isNull);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(LocalDatabase.close);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('basa_import_run_').path;
    ctx = await AppContext.open(dataDir: dir);
    db = ctx.localDb;
    writer = _FailingWriter(PhilIriImportWriterSqlite(db));
    vm = build();

    await db.insert('schools', {'id': _school, 'school_id': '303988', 'school_name': 'ZZ Run High'});
    for (final (id, name) in [(_iron, 'IRON'), (_silver, 'SILVER')]) {
      await db.insert('sections',
          {'id': id, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': name});
    }
    // IRON: 9861-9863; SILVER: 9871-9872 (listed out of name order).
    for (final (id, last, first, sex, section) in [
      (9861, 'Dela Cruz', 'Juan', 'M', _iron),
      (9862, 'Reyes', 'Mark', 'M', _iron),
      (9863, 'Santos', 'Ana', 'F', _iron),
      (9871, 'Zamora', 'Zed', 'M', _silver),
      (9872, 'Abad', 'Amy', 'F', _silver),
    ]) {
      await db.insert('students',
          {'id': id, 'lrn': '99999997$id', 'last_name': last, 'first_name': first, 'sex': sex, 'school_id': _school});
      await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 9951, 'name': 'ZZ Graded', 'is_grade_leveled': 1});
    for (final (id, title, set) in [(_dust, 'Dust', 'C1'), (_diving, 'Diving', 'A2')]) {
      await db.insert('phil_iri_passages', {'id': id, 'collection_id': 9951, 'level': 7, 'title': title,
          'set_code': set, 'body': List.filled(150, 'word').join(' '), 'word_count': 150, 'is_active': 1});
      for (var q = 1; q <= 8; q++) {
        await db.insert('phil_iri_questions', {'id': id * 100 + q, 'passage_id': id, 'question_no': q,
            'prompt': 'Q$q', 'choices': '["a","b","c"]', 'answer_key': 'a'});
      }
    }
    for (final (round, opens) in [('bosy', '2027-06-15'), ('mosy1', '2027-09-01')]) {
      await db.insert('assessment_calendar', {'school_year': _year, 'instrument': 'phil_iri', 'round': round,
          'opens_on': opens, 'closes_on': '${opens.substring(0, 8)}28'});
    }
    await signInAs(_coord, 'coord@zz', 'coordinator');
  });

  WbSheet iron({String name = '01', bool mosy2 = false}) => WbSheet(
        name,
        section: 'IRON',
        schoolYear: _year,
        males: [
          WbLearner('DELA CRUZ, Juan', gst: 30, rounds: {
            PhilIriRound.bosy: const WbRound(passage: '7C Dust', wordsRead: 120, omission: 2, comprehension: 6),
            PhilIriRound.mosy1: const WbRound(passage: '7A2 Diving', wordsRead: 100, comprehension: 5),
            if (mosy2) PhilIriRound.mosy2: const WbRound(wordsRead: 90, comprehension: 4),
          }),
          const WbLearner('Reyes, Mark', gst: 20),
        ],
        females: const [
          WbLearner('Santos, Ana', rounds: {PhilIriRound.bosy: WbRound(passage: '7C Dust', wordsRead: 90)}),
        ],
      );

  WbSheet silver({String name = '02'}) => WbSheet(name, section: 'SILVER', schoolYear: _year, males: const [
        WbLearner('Zamora, Zed', gst: 12, rounds: {PhilIriRound.bosy: WbRound(passage: '7A2 Diving', wordsRead: 80)}),
      ]);

  Future<(List<int>, PhilIriImportPreview)> preview(List<WbSheet> sheets,
      {Map<PhilIriRound, String> dates = const {}}) async {
    final bytes = buildPhilIriWorkbook(sheets);
    return (bytes, await vm.previewWorkbook(bytes, choices: PhilIriImportChoices(dates: dates)));
  }

  Matcher refused(Object message) =>
      throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

  test('imports a workbook section and locks it', () async {
    final (bytes, p) = await preview([iron(), silver()]);
    final result = await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint);
    expect(result.failed, isEmpty);
    expect(result.sessionIds, hasLength(3));
    expect(result.gstIds, hasLength(2));
    expect(result.sessionIds.every((id) => id < 0), isTrue);

    final sessions = await db.query('phil_iri_assessments', where: 'section_id = ?', whereArgs: [_iron]);
    expect(sessions, hasLength(3));
    expect(sessions.map((s) => s['status']).toSet(), {'completed'});
    expect(sessions.map((s) => s['import_source']).toSet(), {'workbook'});
    expect(sessions.where((s) => s['round'] == 'bosy').map((s) => s['assessed_at']).toSet(), {'2027-06-15'});
    final miscues = await db.rawQuery('SELECT m.word_index FROM phil_iri_miscues m '
        'JOIN phil_iri_readings r ON r.id = m.reading_id JOIN phil_iri_assessments a ON a.id = r.assessment_id '
        'WHERE a.student_id = 9861');
    expect(miscues, hasLength(2));
    expect(miscues.every((m) => m['word_index'] == null), isTrue);
    expect(await db.query('phil_iri_workbook_imports', where: 'section_id = ?', whereArgs: [_iron]), hasLength(1));
    expect(writer.locks, hasLength(1), reason: 'one lock, in a learner transaction');
    expect(await db.query('phil_iri_workbook_imports', where: 'section_id = ?', whereArgs: [_silver]), isEmpty);
  });

  // Command pass r32 (a7): the workbook's "# of Words Read" of a whole-text
  // reading is the passage's words; the reading row takes words read only
  // for one minute (CHECK on both sides), so it must not travel.
  test('a whole-text reading with its typed words read imports (words read not stored)', () async {
    final sheet = WbSheet('01', section: 'IRON', schoolYear: _year, methods: const {
      PhilIriRound.bosy: 'Whole-Text Reading',
    }, males: const [
      WbLearner('DELA CRUZ, Juan', gst: 30, rounds: {
        PhilIriRound.bosy: WbRound(passage: '7C Dust', wordsRead: 120, mm: 2, ss: 30, omission: 2, comprehension: 6),
      }),
    ]);
    final (bytes, p) = await preview([sheet]);
    final result = await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint);
    expect(result.failed, isEmpty);
    expect(result.sessionIds, hasLength(1));
    final reading = (await db.query('phil_iri_readings', where: 'assessment_id = ?', whereArgs: [result.sessionIds.single]))
        .single;
    expect(reading['method'], 'whole_text');
    expect(reading['reading_seconds'], 150);
    expect(reading['words_read'], isNull);
  });

  test('second import of the section is refused', () async {
    final (bytes, p) = await preview([iron()]);
    await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint);
    final again = await vm.previewWorkbook(bytes);
    expect(again.sections.single.status, PhilIriImportSectionPreview.alreadyImported);
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: again.fingerprint),
        refused("Sheet 01 can't be imported: already imported."));
  });

  test('ticks: nothing ticked, unknown sheet, two sheets of one section', () async {
    final (bytes, p) = await preview([iron(), iron(name: '07')]);
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(), fingerprint: p.fingerprint),
        refused('Tick at least one section.'));
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'99'}), fingerprint: p.fingerprint),
        refused('There is no section sheet 99 in this workbook.'));
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01', '07'}), fingerprint: p.fingerprint),
        refused('sheets 01 and 07 both name section IRON: tick one'));
    expect(await db.query('phil_iri_assessments'), isEmpty);
  });

  test('stale preview refused', () async {
    final (bytes, p) = await preview([iron()]);
    await db.insert('phil_iri_assessments', {'id': 7101, 'student_id': 9863, 'school_id': _school,
        'section_id': _iron, 'school_year': _year, 'round': 'bosy', 'status': 'in_progress',
        'assessed_at': '2027-06-17', 'row_version': 1});
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint),
        refused('The data changed since the preview. Preview again before importing.'));
    expect(await db.query('phil_iri_assessments'), hasLength(1));
  });

  test('missing round date refused; a given date is used; not a date refused', () async {
    final (bytes, p) = await preview([iron(mosy2: true)]);
    expect(p.proposedDates[PhilIriRound.mosy2], isNull);
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint),
        refused('Give a date for MOSY #2.'));

    const bad = PhilIriImportChoices(sheets: {'01'}, dates: {PhilIriRound.mosy2: '2027-02-30'});
    final pBad = await vm.previewWorkbook(bytes, choices: bad);
    expect(() => vm.importWorkbook(bytes, bad, fingerprint: pBad.fingerprint),
        refused('MOSY #2: 2027-02-30 is not a date (YYYY-MM-DD).'));

    const outside = PhilIriImportChoices(sheets: {'01'}, dates: {PhilIriRound.mosy2: '2026-11-10'});
    final pOutside = await vm.previewWorkbook(bytes, choices: outside);
    expect(() => vm.importWorkbook(bytes, outside, fingerprint: pOutside.fingerprint),
        refused('MOSY #2: 2026-11-10 is outside school year 2027-2028.'));

    const future = PhilIriImportChoices(sheets: {'01'}, dates: {PhilIriRound.mosy2: '2028-07-20'});
    final pFuture = await build().previewWorkbook(bytes, choices: future);
    final early = PhilIriImportViewModel(
      auth: ctx.authVm,
      philIri: wireTutor(ctx, wireShared(ctx)).philIriVm,
      calendar: wireTutor(ctx, wireShared(ctx)).calendarVm,
      sessions: PhilIriAssessmentRepositorySqlite(db),
      gst: PhilIriGstRepositorySqlite(db),
      passages: PhilIriPassageRepositorySqlite(db),
      collections: PhilIriCollectionRepositorySqlite(db),
      schools: SchoolRepositorySqlite(db),
      sections: SectionRepositorySqlite(db),
      students: StudentRepositorySqlite(db),
      writer: writer,
      uploadLocal: SyncUploadLocalSqlite(db),
      headersDir: dir,
      now: () => DateTime(2028, 7, 1),
    );
    expect(() => early.importWorkbook(bytes, future, fingerprint: pFuture.fingerprint),
        refused('MOSY #2: 2028-07-20 is in the future.'));

    const good = PhilIriImportChoices(sheets: {'01'}, dates: {PhilIriRound.mosy2: '2027-11-10'});
    final pGood = await vm.previewWorkbook(bytes, choices: good);
    await vm.importWorkbook(bytes, good, fingerprint: pGood.fingerprint);
    final mosy2 = await db.query('phil_iri_assessments', where: "round = 'mosy2'");
    expect(mosy2.single['assessed_at'], '2027-11-10');
  });

  test('too much for one upload refused with how many fit', () async {
    final (bytes, p) = await preview([iron(), silver()]);
    final iron1 = p.sections.firstWhere((s) => s.ref.sheet == '01');
    final silver1 = p.sections.firstWhere((s) => s.ref.sheet == '02');
    const both = PhilIriImportChoices(sheets: {'01', '02'});

    vm = build(maxBytes: p.unsentBytes + iron1.uploadBytes + silver1.uploadBytes - 1);
    expect(() => vm.importWorkbook(bytes, both, fingerprint: p.fingerprint),
        refused('Too much for one upload: 1 of the ticked sections fit (01 IRON). Import them, upload, then import the rest.'));

    vm = build(maxBytes: iron1.uploadBytes - 1);
    expect(() => vm.importWorkbook(bytes, both, fingerprint: p.fingerprint),
        refused('Too much for one upload: sheet 01 IRON alone is ${(iron1.uploadBytes / 1024).ceil()} KB, '
            'more than one upload (${((iron1.uploadBytes - 1) / 1024).floor()} KB).'));
    expect(await db.query('phil_iri_assessments'), isEmpty);
  });

  test('failed learner reported, others imported; the lock written alone when the last fails', () async {
    final (bytes, p) = await preview([iron()]);
    writer.failFor = 9863; // Santos, Ana: the section's last learner
    final result = await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint);
    expect(result.failed.keys.single, contains('sheet 01'));
    expect(result.failed.values.single, contains('device refused learner 9863'));
    expect(result.sessionIds, hasLength(2));
    expect(await db.query('phil_iri_assessments', where: 'student_id = 9863'), isEmpty);
    expect(await db.query('phil_iri_workbook_imports', where: 'section_id = ?', whereArgs: [_iron]), hasLength(1));
  });

  test('every learner failed: no lock', () async {
    final (bytes, p) = await preview([silver()]);
    writer.failFor = 9871;
    final result = await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'02'}), fingerprint: p.fingerprint);
    expect(result.failed, hasLength(1));
    expect(await db.query('phil_iri_workbook_imports'), isEmpty);
  });

  test('a ticked section with nothing to import is not locked', () async {
    final (bytes, p) = await preview(
        [WbSheet('03', section: 'SILVER', schoolYear: _year, males: const [WbLearner('Nobody, Here', gst: 5)])]);
    final result = await vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'03'}), fingerprint: p.fingerprint);
    expect(result.nothingToImport, ['03']);
    expect(await db.query('phil_iri_workbook_imports'), isEmpty);
  });

  test('template lists the section\'s learners; scoresheet import twice skips what is there', () async {
    final template = await vm.scoresheetTemplate(_silver);
    final wb = XlsxWorkbook.decode(template);
    final cells = wb.readSheet('Learners');
    String col(String label) {
      for (final e in cells.entries) {
        final (c, r) = splitRef(e.key);
        if (r == 1 && e.value == label) return columnLetters(c);
      }
      throw StateError(label);
    }

    expect(cells['${col('LRN')}2'], '999999979872', reason: 'Abad before Zamora');
    expect(cells['${col('LRN')}3'], '999999979871');
    expect(cells['${col('LRN')}4'], isNull);

    wb.write('Learners', {
      '${col('Round')}2': 'BOSY', '${col('Date')}2': '2027-06-20', '${col('Passage')}2': 'G7C1 Dust',
      '${col('Method')}2': 'whole text', '${col('Time')}2': '1:40', '${col('Q1')}2': 'a',
      '${col('Round')}3': 'GST', '${col('Date')}3': '2027-06-18', '${col('GST score')}3': 25,
    });
    final file = wb.encode();
    final p1 = await vm.previewScoresheet(_silver, file, 'silver.xlsx');
    final r1 = await vm.importScoresheet(_silver, file, 'silver.xlsx', fingerprint: p1.fingerprint);
    expect(r1.sessionIds, hasLength(1));
    expect(r1.gstIds, hasLength(1));
    final s = await db.query('phil_iri_assessments', where: 'section_id = ?', whereArgs: [_silver]);
    expect(s.single['import_source'], 'scoresheet');
    expect(await db.query('phil_iri_workbook_imports'), isEmpty, reason: 'a scoresheet never locks');

    final p2 = await vm.previewScoresheet(_silver, file, 'silver.xlsx');
    expect(p2.sections.single.rows.every((r) => r.outcome == PhilIriImportOutcome.skipped), isTrue);
    final r2 = await vm.importScoresheet(_silver, file, 'silver.xlsx', fingerprint: p2.fingerprint);
    expect(r2.sessionIds, isEmpty);
    expect(r2.gstIds, isEmpty);
    expect(await db.query('phil_iri_assessments', where: 'section_id = ?', whereArgs: [_silver]), hasLength(1));
  });

  test('header labels: set, list, reset', () async {
    expect(await vm.headerLabels(), containsPair('wb.name', isNotEmpty));
    expect(await vm.setHeader('ss.lrn', 'Learner Reference No.'), isNull);
    expect((await vm.headerLabels())['ss.lrn'], 'Learner Reference No.');
    await vm.resetHeaders();
    expect((await vm.headerLabels())['ss.lrn'], 'LRN');
  });

  test('tutor refused with the exact message', () async {
    final (bytes, p) = await preview([iron()]);
    await signInAs(_tutor, 'tutor@zz', 'tutor');
    final forbidden = refused(PhilIriImportViewModel.forbiddenMessage);
    expect(() => vm.importWorkbook(bytes, const PhilIriImportChoices(sheets: {'01'}), fingerprint: p.fingerprint), forbidden);
    expect(() => vm.scoresheetTemplate(_silver), forbidden);
    expect(() => vm.setHeader('ss.lrn', 'X'), forbidden);
  });
}
