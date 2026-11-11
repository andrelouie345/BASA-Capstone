// Phil-IRI import, Task 9: the preview (spec 2026-11-09-phil-iri-import-design,
// PhilIriImportViewModel; Task 9 rulings in the import ledger). Signed in
// offline as the school's coordinator; a Grade 7 school with pool-like
// passages, a workbook built with the Task 6 fixture (made-up names).
import 'dart:convert';
import 'dart:io';

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
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/models/phil_iri_workbook_import.dart';
import 'package:basa_capstone/core/models/section.dart';
import 'package:basa_capstone/core/repositories/phil_iri_import_writer.dart';
import 'package:basa_capstone/core/services/phil_iri_import_headers.dart';
import 'package:basa_capstone/core/services/phil_iri_scoresheet_template.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/phil_iri_import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/sync_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';
import '../helpers/phil_iri_workbook_fixture.dart';

const _school = 9801;
const _otherSchool = 9802;
const _year = '2027-2028';
const _coord = '00000000-0000-0000-0000-0000000098c1';
const _tutor = '00000000-0000-0000-0000-0000000098a1';
const _iron = 9810, _silver = 9811, _gold = 9812;

// Learners of IRON (id -> last, first, middle, sex).
const _learners = {
  9801: ('Dela Cruz', 'Juan', 'Mendoza', 'M'),
  9802: ('Reyes', 'Mark', 'Lim', 'M'),
  9803: ('Reyes', 'Mark', 'Lopez', 'M'),
  9804: ('Go', 'Max', null, 'F'), // the file says male
  9805: ('Cruz', 'Ben', null, 'M'), // BOSY already completed
  9806: ('Lim', 'Joy', null, 'F'), // BOSY in progress live
  9807: ('Tan', 'Leo', null, 'M'), // GST already recorded
  9808: ('Uy', 'Kim', null, 'F'), // read Dust in BOSY already
  9809: ('Santos', 'Ana', null, 'F'),
  9810: ('Ong', 'Mia', null, 'F'),
};

// Passages: Dust 8 questions, Diving 10, Ecosystems 8, Pam's Cat (Grade 2).
const _dust = 9901, _diving = 9902, _eco = 9903, _pam = 9904;

void main() {
  late AppContext ctx;
  late Database db;
  late PhilIriImportViewModel vm;
  late PhilIriImportWriter writer;

  Future<void> signInAs(String id, String email, String role) async {
    await seedOfflineOwner(db, userId: id, email: email, role: role, schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: email, password: 'test-pw'), isNull);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('basa_import_preview_');
    ctx = await AppContext.open(dataDir: dir.path);
    db = ctx.localDb;
    final shared = wireShared(ctx);
    final t = wireTutor(ctx, shared);
    writer = PhilIriImportWriterSqlite(db);
    vm = PhilIriImportViewModel(
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
      headersDir: dir.path,
    );

    await db.insert('schools', {'id': _school, 'school_id': '303988', 'school_name': 'ZZ Import High'});
    await db.insert('schools', {'id': _otherSchool, 'school_id': '111111', 'school_name': 'ZZ Other High'});
    for (final (id, name) in [(_iron, 'IRON'), (_silver, 'SILVER'), (_gold, 'GOLD')]) {
      await db.insert('sections',
          {'id': id, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': name});
    }
    for (final e in _learners.entries) {
      final (last, first, middle, sex) = e.value;
      await db.insert('students', {'id': e.key, 'lrn': '99999998${e.key}', 'last_name': last, 'first_name': first,
          'middle_name': middle, 'sex': sex, 'school_id': _school});
      await db.insert('enrollments', {'student_id': e.key, 'section_id': _iron, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('students', {'id': 9820, 'lrn': '999999989820', 'last_name': 'Gold', 'first_name': 'One',
        'sex': 'M', 'school_id': _school});
    await db.insert('enrollments', {'student_id': 9820, 'section_id': _gold, 'school_year': _year, 'status': 'active'});

    await db.insert('phil_iri_collections', {'id': 9901, 'name': 'ZZ Graded', 'is_grade_leveled': 1});
    Future<void> passage(int id, int level, String title, String? set, int questions) async {
      await db.insert('phil_iri_passages', {'id': id, 'collection_id': 9901, 'level': level, 'title': title,
          'set_code': set, 'body': List.filled(150, 'word').join(' '), 'word_count': 150, 'is_active': 1});
      for (var q = 1; q <= questions; q++) {
        await db.insert('phil_iri_questions', {'id': id * 100 + q, 'passage_id': id, 'question_no': q,
            'prompt': 'Q$q', 'choices': '["a","b","c"]', 'answer_key': 'a'});
      }
    }
    await passage(_dust, 7, 'Dust', 'C1', 8);
    await passage(_diving, 7, 'Diving', 'A2', 10);
    await passage(_eco, 7, 'Ecosystems', 'D2', 8);
    await passage(_pam, 2, "Pam's Cat", 'A', 5);

    for (final (round, opens) in [('bosy', '2027-06-15'), ('mosy1', '2027-09-01')]) {
      await db.insert('assessment_calendar', {'school_year': _year, 'instrument': 'phil_iri', 'round': round,
          'opens_on': opens, 'closes_on': '${opens.substring(0, 8)}28'});
    }
    // GOLD's workbook was imported already (a pulled lock row).
    await db.insert('phil_iri_workbook_imports',
        {'id': 501, 'school_id': _school, 'section_id': _gold, 'school_year': _year, 'row_version': 1});

    await signInAs(_coord, 'coord@zz', 'coordinator');

    // What BASA has already.
    PhilIriImportedSession done(int student, PhilIriRound round, int passageId) => PhilIriImportedSession(
          assessment: PhilIriAssessment(studentId: student, schoolId: _school, sectionId: _iron, schoolYear: _year,
              round: round, assessedAt: '2027-06-16', importSource: PhilIriImportSource.workbook),
          reading: PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: passageId,
              method: PhilIriReadingMethod.oneMinute, wordsRead: 90),
        );
    await writer.writeLearner(sessions: [done(9805, PhilIriRound.bosy, _eco)]);
    await writer.writeLearner(sessions: [done(9808, PhilIriRound.bosy, _dust)]);
    await db.insert('phil_iri_assessments', {'id': 7001, 'student_id': 9806, 'school_id': _school,
        'section_id': _iron, 'school_year': _year, 'round': 'bosy', 'status': 'in_progress', 'assessed_at': '2027-06-17', 'row_version': 1});
    await db.insert('phil_iri_gst_results', {'id': 7002, 'student_id': 9807, 'school_id': _school,
        'section_id': _iron, 'school_year': _year, 'max_score': 40, 'total_score': 20, 'taken_at': '2027-06-15', 'attempt_no': 1, 'row_version': 1});
  });

  WbSheet iron({String name = '01', Map<String, String> renames = const {}}) => WbSheet(
        name,
        section: 'IRON',
        schoolYear: _year,
        comprehensionMax: const {PhilIriRound.mosy3: null},
        renames: renames,
        males: const [
          WbLearner('DELA CRUZ, Juan M.', gst: 30, rounds: {
            PhilIriRound.bosy: WbRound(passage: '7C Dust', wordsRead: 120, omission: 2, reversal: 1, repetition: 3,
                comprehension: 6, adjProfile: 'Non-Reader', adjLevel: 0),
            PhilIriRound.mosy1: WbRound(passage: '7A2 Diving', wordsRead: 100, comprehension: 6), // 6/8 -> 8/10
            PhilIriRound.mosy2: WbRound(passage: '7C Dust', comprehension: 15), // re-read, 15/20 -> 6/8
          }),
          WbLearner('Reyes, Mark L.', gst: 20),
          WbLearner('Go, Max', gst: 21),
          WbLearner('Cruz, Ben', rounds: {PhilIriRound.bosy: WbRound(passage: '7C Dust', wordsRead: 100)}),
          WbLearner('Tan, Leo', gst: 25, rounds: {PhilIriRound.bosy: WbRound(passage: "2A Pam's Cat", wordsRead: 90)}),
          WbLearner('Nobody, Here', gst: 10),
        ],
        females: const [
          WbLearner('Santos, Ana', gst: 10, rounds: {
            PhilIriRound.bosy: WbRound(passage: '7Z Unknown Story', wordsRead: 80),
            PhilIriRound.mosy1: WbRound(wordsRead: 90, comprehension: 5), // Untitled
            PhilIriRound.mosy2: WbRound(wordsRead: 70, comprehension: 25), // above its 20: dropped by the reader
            PhilIriRound.mosy3: WbRound(passage: '7A2 Diving', wordsRead: 80, comprehension: 12), // no max, 12 > 10
          }),
          WbLearner('Lim, Joy', rounds: {PhilIriRound.bosy: WbRound(passage: '7C Dust', wordsRead: 100)}),
          WbLearner('Uy, Kim', rounds: {PhilIriRound.mosy1: WbRound(passage: '7C Dust', wordsRead: 110)}),
          WbLearner('Ong, Mia', rounds: {PhilIriRound.bosy: WbRound(passage: '7C Dust')}), // passage only
        ],
      );

  List<int> workbook() => buildPhilIriWorkbook([
        iron(),
        WbSheet('02', section: 'SILVER', schoolYear: _year),
        WbSheet('03', section: 'COPPER', schoolYear: _year, males: const [WbLearner('Some, One', gst: 5)]),
        WbSheet('04', section: 'GOLD', schoolYear: _year, males: const [WbLearner('Gold, One', gst: 5)]),
        WbSheet('05', section: 'IRON', school: '111111 - OTHER', schoolYear: _year,
            males: const [WbLearner('Some, One', gst: 5)]),
      ]);

  PhilIriImportSectionPreview sheet(PhilIriImportPreview p, String name) => p.sections.firstWhere((s) => s.ref.sheet == name);

  List<PhilIriImportRow> rowsOf(PhilIriImportSectionPreview s, String learner) =>
      s.rows.where((r) => r.learner.name == learner).toList();

  PhilIriImportRow reading(PhilIriImportSectionPreview s, String learner, PhilIriRound round) =>
      rowsOf(s, learner).firstWhere((r) => r.round == round && r.gst == null);

  PhilIriImportRow gstOf(PhilIriImportSectionPreview s, String learner) =>
      rowsOf(s, learner).firstWhere((r) => r.gst != null);

  test('section statuses: importable, empty, not in BASA (named), already imported, another school', () async {
    final p = await vm.previewWorkbook(workbook());
    expect(p.headerIssues, isEmpty);
    expect(sheet(p, '01').status, PhilIriImportSectionPreview.importable);
    expect(sheet(p, '01').section!.id, _iron);
    expect(sheet(p, '02').status, PhilIriImportSectionPreview.empty);
    expect(sheet(p, '03').status, PhilIriImportSectionPreview.notInBasa);
    expect(sheet(p, '03').notes.single, contains('COPPER'));
    expect(sheet(p, '04').status, PhilIriImportSectionPreview.alreadyImported);
    expect(sheet(p, '05').status, PhilIriImportSectionPreview.notInBasa);
    expect(sheet(p, '05').notes.single, contains("another school's section"));
    expect(sheet(p, '04').rows, isEmpty);
    expect(p.oneTimeWarning,
        "This makes BASA the record for this section's school year. You can't import this section's workbook again.");
  });

  test('learners: matched by name, two candidates / sex mismatch / no match need a pick; picks apply', () async {
    final s = sheet(await vm.previewWorkbook(workbook()), '01');
    expect(gstOf(s, 'DELA CRUZ, Juan M.').student!.id, 9801);
    final mark = gstOf(s, 'Reyes, Mark L.');
    expect(mark.outcome, PhilIriImportOutcome.skipped);
    expect(mark.notes.single, 'needs a pick');
    expect(mark.candidates.take(2).map((c) => c.id), [9802, 9803]);
    expect(gstOf(s, 'Go, Max').notes.single, 'needs a pick', reason: 'sex mismatch');
    expect(gstOf(s, 'Nobody, Here').candidates, hasLength(_learners.length));

    final picked = sheet(
        await vm.previewWorkbook(workbook(),
            choices: PhilIriImportChoices(picks: {mark.learnerRef: 9803, gstOf(s, 'Go, Max').learnerRef: 9804})),
        '01');
    expect(gstOf(picked, 'Reyes, Mark L.').student!.id, 9803);
    expect(gstOf(picked, 'Reyes, Mark L.').outcome, PhilIriImportOutcome.import);
    expect(gstOf(picked, 'Go, Max').student!.id, 9804);
  });

  test('two file learners on one BASA learner both need a pick', () async {
    final p = await vm.previewWorkbook(buildPhilIriWorkbook([
      WbSheet('01', section: 'IRON', schoolYear: _year,
          males: const [WbLearner('Cruz, Ben', gst: 5), WbLearner('Ben Cruz', gst: 6)]),
    ]));
    final rows = sheet(p, '01').rows;
    expect(rows, hasLength(2));
    for (final r in rows) {
      expect(r.student, isNull);
      expect(r.notes.single, startsWith('needs a pick: matched twice'));
    }
  });

  test('two sheets naming one section are both noted', () async {
    final p = await vm.previewWorkbook(buildPhilIriWorkbook([
      WbSheet('01', section: 'IRON', schoolYear: _year, males: const [WbLearner('Cruz, Ben', gst: 5)]),
      WbSheet('07', section: 'Iron', schoolYear: _year, males: const [WbLearner('Tan, Leo', gst: 5)]),
    ]));
    for (final name in ['01', '07']) {
      expect(sheet(p, name).notes, contains('sheets 01 and 07 both name section IRON: tick one'));
    }
  });

  test('re-read flagged, lower-grade and unknown passages skipped, reader skips listed', () async {
    final s = sheet(await vm.previewWorkbook(workbook()), '01');
    final kim = reading(s, 'Uy, Kim', PhilIriRound.mosy1);
    expect(kim.outcome, PhilIriImportOutcome.importFlagged);
    expect(kim.notes, contains('re-read of Dust (read in BOSY)'));
    final juanMosy2 = reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.mosy2);
    expect(juanMosy2.notes, contains('re-read of Dust (read in BOSY)'), reason: 'read earlier in the same file');

    final leo = reading(s, 'Tan, Leo', PhilIriRound.bosy);
    expect(leo.outcome, PhilIriImportOutcome.skipped);
    expect(leo.notes.single, "lower-grade passage (Pam's Cat, Grade 2)");
    expect(reading(s, 'Santos, Ana', PhilIriRound.bosy).notes.single, 'passage not in BASA: 7Z Unknown Story');
    final mia = reading(s, 'Ong, Mia', PhilIriRound.bosy);
    expect(mia.skip, isNotNull);
    expect(mia.notes.single, startsWith('incomplete'));
  });

  test('Untitled flagged, comprehension-only imported, Untitled above its total dropped by the reader', () async {
    final p = await vm.previewWorkbook(workbook());
    final s = sheet(p, '01');
    final untitled = reading(s, 'Santos, Ana', PhilIriRound.mosy1);
    expect(untitled.outcome, PhilIriImportOutcome.importFlagged);
    expect(untitled.notes, contains('no passage (Untitled)'));
    expect(untitled.session!.reading.passageId, isNull);
    expect(untitled.session!.reading.importedCorrect, 5);
    expect(untitled.session!.reading.importedTotal, 8);
    expect(untitled.basaProfile, isNotNull);

    final juanMosy2 = reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.mosy2);
    expect(juanMosy2.session!.reading.readingSeconds, isNull);
    expect(juanMosy2.session!.reading.wordsRead, isNull);
    expect(juanMosy2.outcome, isNot(PhilIriImportOutcome.skipped));

    final above = reading(s, 'Santos, Ana', PhilIriRound.mosy2);
    expect(above.session!.reading.importedCorrect, isNull);
    expect(p.plan.problems.map((x) => x.message), contains('comprehension 25 is more than the maximum 20, not imported'));
  });

  test('comprehension on another scale is scaled; above the questions with no maximum is unreadable', () async {
    final s = sheet(await vm.previewWorkbook(workbook()), '01');
    final diving = reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.mosy1);
    expect(diving.notes, contains('comprehension 6 of 8 scaled to 8 of 10'));
    expect(diving.session!.reading.importedCorrect, 8);
    final dust2 = reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.mosy2);
    expect(dust2.notes, contains('comprehension 15 of 20 scaled to 6 of 8'));
    expect(dust2.session!.reading.importedCorrect, 6);
    // BOSY Dust: 6 of 8 on an 8-question passage, no scaling.
    expect(reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.bosy).session!.reading.importedCorrect, 6);

    final over = reading(s, 'Santos, Ana', PhilIriRound.mosy3);
    expect(over.outcome, PhilIriImportOutcome.skipped);
    expect(over.notes.single, matches(RegExp(r'^sheet 01, row \d+: comprehension 12 is more than the 10 questions of Diving')));
  });

  test('already assessed, in progress live and GST already recorded are skipped', () async {
    final s = sheet(await vm.previewWorkbook(workbook()), '01');
    expect(reading(s, 'Cruz, Ben', PhilIriRound.bosy).notes.single, 'already assessed this round');
    expect(reading(s, 'Lim, Joy', PhilIriRound.bosy).notes.single, 'live session in progress');
    expect(gstOf(s, 'Tan, Leo').notes.single, 'GST already recorded this school year');
  });

  test('GST out of another maximum is scaled to the grade maximum; above the file maximum is unreadable', () async {
    final wb = XlsxWorkbook.decode(workbook());
    wb.write('01', {'G12': 20});
    final s = sheet(await vm.previewWorkbook(wb.encode()), '01');
    final ana = gstOf(s, 'Santos, Ana');
    expect(ana.outcome, PhilIriImportOutcome.importFlagged);
    expect(ana.notes.single, 'GST 10 of 20 scaled to 20 of 40');
    expect(ana.gstResult!.totalScore, 20);
    expect(ana.gstResult!.maxScore, 40);
    expect(gstOf(s, 'DELA CRUZ, Juan M.').notes.single, contains('GST 30 is more than the maximum 20'));
  });

  test('proposed dates come from the calendar; chosen dates win', () async {
    final p = await vm.previewWorkbook(workbook());
    expect(p.proposedDates[PhilIriRound.bosy], '2027-06-15');
    expect(p.proposedDates[PhilIriRound.mosy1], '2027-09-01');
    expect(p.proposedDates[PhilIriRound.mosy2], isNull);
    final s = sheet(p, '01');
    expect(reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.bosy).session!.assessment.assessedAt, '2027-06-15');
    expect(gstOf(s, 'DELA CRUZ, Juan M.').gstResult!.takenAt, '2027-06-15', reason: 'the GST takes the BOSY date');

    final chosen = await vm.previewWorkbook(workbook(),
        choices: const PhilIriImportChoices(dates: {PhilIriRound.mosy2: '2027-11-10'}));
    expect(chosen.proposedDates[PhilIriRound.mosy2], '2027-11-10');
    expect(reading(sheet(chosen, '01'), 'DELA CRUZ, Juan M.', PhilIriRound.mosy2).session!.assessment.assessedAt,
        '2027-11-10');
    expect(chosen.fingerprint, isNot(p.fingerprint));
    expect((await vm.previewWorkbook(workbook())).fingerprint, p.fingerprint, reason: 'same data, same fingerprint');
  });

  test('levels that differ from the workbook are listed; D4 miscues', () async {
    final s = sheet(await vm.previewWorkbook(workbook()), '01');
    final bosy = reading(s, 'DELA CRUZ, Juan M.', PhilIriRound.bosy);
    expect(bosy.basaProfile, isNotNull);
    expect(bosy.outcome, PhilIriImportOutcome.importFlagged);
    expect(bosy.notes.single,
        'levels differ: BASA ${bosy.basaProfile} (grade ${bosy.basaAdjustedLevel}), workbook Non-Reader (grade 0)');
    final miscues = bosy.session!.miscues;
    expect(miscues.where((m) => m.counts), hasLength(3)); // omission 2 + reversal 1
    expect(miscues.where((m) => m.selfCorrected), hasLength(3));
    expect(miscues.every((m) => m.wordIndex == null), isTrue);
  });

  test('header issues stop the preview; headerSamples shows values, never names', () async {
    final renamed = buildPhilIriWorkbook([iron(renames: const {'# of Words Read': 'Words'})]);
    final p = await vm.previewWorkbook(renamed);
    expect(p.headerIssues.map((i) => i.field), contains('wb.wordsRead'));
    expect(p.sections, isEmpty);

    final samples = await vm.headerSamples(renamed, 'wb.wordsRead', 'Words');
    expect(samples.first, '120');
    expect(() => vm.headerSamples(renamed, 'wb.name', 'NAME OF STUDENT'),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'Names are not shown here.')));
  });

  test('scoresheet: by LRN, answers marked from the key, blanks flagged, unknown LRN skipped', () async {
    final headers = await PhilIriImportHeaders.load(Directory.systemTemp.createTempSync('basa_ss_').path);
    final section = Section(id: _iron, schoolId: _school, schoolYear: _year, gradeLevel: '7', sectionName: 'IRON');
    final template = buildPhilIriScoresheetTemplate(
        section: section,
        learners: await StudentRepositorySqlite(db).getBySection(_iron),
        passages: await PhilIriPassageRepositorySqlite(db).getForLevel(7),
        headers: headers);
    final wb = XlsxWorkbook.decode(template);
    final head = wb.readSheet('Learners');
    String col(String label) {
      for (final e in head.entries) {
        final (c, r) = splitRef(e.key);
        if (r == 1 && e.value == label) return columnLetters(c);
      }
      throw StateError(label);
    }

    wb.write('Learners', {
      for (var r = 2; r <= 20; r++) '${col('LRN')}$r': null,
      '${col('LRN')}2': '999999989801', '${col('Round')}2': 'BOSY', '${col('Date')}2': '2027-06-20',
      '${col('Passage')}2': 'G7C1 Dust', '${col('Method')}2': 'whole text', '${col('Time')}2': '1:40',
      '${col('Q1')}2': 'a', '${col('Q2')}2': 'B', '${col('Q3')}2': 'a',
      '${col('LRN')}3': '999999999999', '${col('Round')}3': 'GST', '${col('Date')}3': '2027-06-20',
      '${col('GST score')}3': 12,
      '${col('LRN')}4': '999999989801', '${col('Round')}4': 'GST', '${col('Date')}4': '2027-06-18',
      '${col('GST score')}4': 30,
    });
    final p = await vm.previewScoresheet(_iron, wb.encode(), 'iron.xlsx');
    final rows = p.sections.single.rows;
    final bosy = rows.firstWhere((r) => r.reading != null);
    expect(bosy.student!.id, 9801);
    expect(bosy.passage!.id, _dust);
    expect(bosy.session!.assessment.importSource, PhilIriImportSource.scoresheet);
    expect(bosy.session!.assessment.assessedAt, '2027-06-20');
    expect(bosy.session!.answers, hasLength(8));
    expect(bosy.session!.answers.where((a) => a.isCorrect), hasLength(2));
    expect(bosy.notes, contains('5 answers blank (counted wrong)'));
    expect(bosy.session!.reading.importedCorrect, isNull);
    expect(rows.firstWhere((r) => r.gst?.score == 12).notes.single,
        'LRN 999999999999 is not an active learner of this section');
    expect(rows.firstWhere((r) => r.gst?.score == 30).gstResult!.takenAt, '2027-06-18');
  });

  test('upload bytes estimated within 5% of what the package gains', () async {
    final p0 = await vm.previewWorkbook(workbook(),
        choices: const PhilIriImportChoices(dates: {PhilIriRound.mosy2: '2027-11-10', PhilIriRound.mosy3: '2028-01-10'}));
    final s = sheet(p0, '01');
    expect(s.uploadBytes, greaterThan(0));
    expect(p0.unsentBytes, greaterThan(0), reason: 'the setup rows are unsent');

    final packageBytes = () async =>
        utf8.encode(jsonEncode((await SyncUploadLocalSqlite(db).buildPackage(release: SyncViewModel.release)).toJson())).length;
    final before = await packageBytes();
    final byStudent = <int, List<PhilIriImportRow>>{};
    for (final r in s.rows.where((r) => r.outcome != PhilIriImportOutcome.skipped)) {
      (byStudent[r.student!.id!] ??= []).add(r);
    }
    final students = byStudent.keys.toList();
    for (final id in students) {
      final rows = byStudent[id]!;
      await writer.writeLearner(
        sessions: [for (final r in rows) if (r.session != null) r.session!],
        gst: rows.where((r) => r.gstResult != null).firstOrNull?.gstResult,
        lock: id == students.last
            ? PhilIriWorkbookImport(schoolId: _school, sectionId: _iron, schoolYear: _year)
            : null,
      );
    }
    final gained = await packageBytes() - before;
    expect((s.uploadBytes - gained).abs() / gained, lessThan(0.05), reason: 'estimated ${s.uploadBytes}, gained $gained');
  });

  test('tutor refused with the exact message', () async {
    await signInAs(_tutor, 'tutor@zz', 'tutor');
    expect(() => vm.previewWorkbook(workbook()),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', PhilIriImportViewModel.forbiddenMessage)));
    expect(PhilIriImportViewModel.forbiddenMessage, 'Forbidden: only an admin or coordinator imports Phil-IRI results.');
  });
}
