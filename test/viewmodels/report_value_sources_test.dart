// The four report switches (spec docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md,
// D1, D5-D8): values_aral, values_bosy_masterlist, values_form2b (and the
// band trend that reads it), values_srp. Under carried every list is today's
// output; under actual a round without a reading of the learner's own is the
// not-assessed stand-in (Struggling, 3 levels down).
//
// One Grade 7 section (91, school 1, 2026-2027), 10 questions per passage,
// one-minute readings of 120 words with no miscues (word reading 100%):
//   A 801  BOSY 9/10, MOSY 1 2/10
//   B 802  GST 30/40 only
//   C 803  BOSY 3/10 only
//   D 804  every round: 5, 6, 6, 7, 9 /10 (EOSY 90%)
//   E 805  a BOSY 9/10 stored under section 92 (same school and year), then
//          moved to 91 without the reading following (Review Focus 1)
//   F 806  BOSY 3/10, MOSY 1 9/10, MOSY 2 2/10; on the ARAL roster
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/models/trend_chart.dart';
import 'package:basa_capstone/core/services/nla_form2b.dart' show NlaBand;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/viewmodels/nla_report_viewmodel.dart';
import 'package:basa_capstone/viewmodels/srp_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _sec = 91, _other = 92;
const a = 801, b = 802, c = 803, d = 804, e = 805, f = 806;
const bosy = PhilIriRound.bosy, mosy1 = PhilIriRound.mosy1, mosy2 = PhilIriRound.mosy2;
final _asOf = DateTime(2026, 11, 14);

void main() {
  late AppContext ctx;
  late TutorVms t;
  late AdminVms adm;

  Future<void> setValues(Map<PhilIriValueList, PhilIriValues> values) async {
    await ctx.localDb.delete('report_settings');
    if (values.isEmpty) return;
    await ctx.localDb.insert('report_settings', {
      'id': 1,
      'school_id': 1,
      'settings': jsonEncode({for (final e in values.entries) e.key.key: e.value.name}),
    });
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_values_reports_').path);
    final s = wireShared(ctx);
    t = wireTutor(ctx, s);
    adm = await wireAdmin(ctx, s, t);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ45', 'school_name': 'ZZ value reports', 'region_id': 13});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab45', email: 'vr@test', role: 'coordinator', schoolId: 1);
    for (final id in [_sec, _other]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S$id'});
    }
    for (final id in [a, b, c, d, e, f]) {
      await db.insert('students',
          {'id': id, 'lrn': '99999999$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1, 'sex': id.isEven ? 'F' : 'M'});
      await db.insert('enrollments',
          {'student_id': id, 'section_id': id == e ? _other : _sec, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded values', 'is_grade_leveled': 1});
    for (var p = 1; p <= 5; p++) {
      final id = 500 + p;
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (var q = 1; q <= 10; q++) {
        await db.insert('phil_iri_questions',
            {'id': id * 100 + q, 'passage_id': id, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    expect(await ctx.authVm.signInOffline(email: 'vr@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    final dates = {
      PhilIriRound.bosy: DateTime(2026, 8, 5),
      PhilIriRound.mosy1: DateTime(2026, 9, 5),
      PhilIriRound.mosy2: DateTime(2026, 10, 5),
      PhilIriRound.mosy3: DateTime(2026, 11, 1),
      PhilIriRound.eosy: DateTime(2026, 11, 10),
    };
    Future<void> read(int student, int section, PhilIriRound round, int passageNo, int correct) async {
      final s = await vm.startSession(
          studentId: student, sectionId: section, schoolYear: _year, round: round, assessedAt: dates[round]);
      final passage = 500 + passageNo;
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var q = 1; q <= 10; q++) {
        await vm.answer(readingId: r.id!, questionId: passage * 100 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await vm.complete(s.id!);
    }

    await read(a, _sec, bosy, 1, 9);
    await read(a, _sec, mosy1, 2, 2);
    await vm.recordGst(studentId: b, sectionId: _sec, schoolYear: _year, totalScore: 30, takenAt: DateTime(2026, 8, 1));
    await read(c, _sec, bosy, 1, 3);
    for (final (i, round) in PhilIriRound.values.indexed) {
      await read(d, _sec, round, i + 1, const [5, 6, 6, 7, 9][i]);
    }
    await read(e, _other, bosy, 1, 9);
    await db.update('enrollments', {'section_id': _sec}, where: 'student_id = ?', whereArgs: [e]);
    await read(f, _sec, bosy, 1, 3);
    await read(f, _sec, mosy1, 2, 9);
    await read(f, _sec, mosy2, 3, 2);
    await t.aralVm.enroll(sectionId: _sec, schoolYear: _year, studentId: f, enteredOn: DateTime(2026, 8, 10));
  });

  // The CSVs start with a byte-order mark; reading the file may drop it.
  String norm(String csv) => csv.replaceAll('\r\n', '\n').replaceFirst('﻿', '');
  String golden(String name) => norm(File('test/viewmodels/golden/$name').readAsStringSync());
  // Today's CSV with the new last column: "Values" in the header, [v] on every row.
  String withValues(String csv, String v) => csv
      .split('\n')
      .indexed
      .map((x) => x.$2.isEmpty ? x.$2 : '${x.$2},${x.$1 == 0 ? 'Values' : v}')
      .join('\n');

  test("carried: every list is today's output, plus the Values column last", () async {
    await setValues({});
    final nla = await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(nla.values, PhilIriValues.carried);
    expect(norm(nlaReportCsv(nla)), withValues(golden('nla_report_carried.csv'), 'carried'));
    final bm = await t.nlaReportVm.bosyMasterlist(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(bm.values, PhilIriValues.carried);
    expect(norm(bosyMasterlistCsv(bm)), withValues(golden('bosy_masterlist_carried.csv'), 'carried'));
    final srp = await t.srpVm.candidates(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(srp.values, PhilIriValues.carried);
    expect(norm(srpListCsv(srp)), withValues(golden('srp_list_carried.csv'), 'carried'));
    final aral = await adm.aralReportVm.implementationReport(schoolId: 1, schoolYear: _year, asOf: _asOf);
    expect(aral.values, PhilIriValues.carried);
    expect(norm(await adm.aralReportVm.implementationReportCsv(schoolId: 1, schoolYear: _year, asOf: _asOf)),
        withValues(golden('aral_report_carried.csv'), 'carried'));
    final b0 = (await t.aralVm.propose(sectionId: _sec, schoolYear: _year)).singleWhere((x) => x.student.id == b);
    expect(b0.reason, 'Phil-IRI BOSY (GST only): Struggling, reads at Grade 6 (no reading, comprehension 75%, - wpm)');
  });

  test('BOSY masterlist, actual: a GST-only learner is not assessed this round', () async {
    await setValues({PhilIriValueList.bosyMasterlist: PhilIriValues.actual});
    final bm = await t.nlaReportVm.bosyMasterlist(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(bm.values, PhilIriValues.actual);
    final byId = {for (final x in bm.sections.single.learners) x.student.id: x};
    expect(byId.keys.toSet(), {b, c, d, e, f});
    expect((byId[b]!.notAssessed, byId[b]!.levelsDown, byId[b]!.adjustedLevel, byId[b]!.comprehension),
        (true, 3, 4, null));
    expect((byId[c]!.notAssessed, byId[c]!.comprehension), (false, 0.3));
    // E's BOSY is under section 92: neither values count it in 91 (Review Focus 1).
    expect(byId[e]!.notAssessed, isTrue);
    expect(norm(bosyMasterlistCsv(bm)).split('\n')[1], endsWith(',yes,actual'));
    // The other switches don't move it.
    await setValues({PhilIriValueList.form2b: PhilIriValues.actual, PhilIriValueList.srp: PhilIriValues.actual});
    final carried = await t.nlaReportVm.bosyMasterlist(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(carried.values, PhilIriValues.carried);
  });

  test('Form 2b, actual: not read this round = 3-LD Frustration; bands add up to the enrolment', () async {
    await setValues({PhilIriValueList.form2b: PhilIriValues.actual});
    final r = await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(r.values, PhilIriValues.actual);
    final row = r.sections.single;
    expect(row.band(mosy1, NlaBand.ld3Frustration).total, 4); // A (20%), B, C, E
    expect(row.band(mosy1, NlaBand.glr).total, 1); // F (90%)
    expect(row.band(mosy1, NlaBand.ld2Independent).total, 1); // D (60%)
    for (final round in PhilIriRound.values) {
      expect(row.assessed(round).total, 6, reason: round.label);
    }
    expect(norm(nlaReportCsv(r)).split('\n')[1], endsWith(',actual; not assessed this round counted as 3-LD Frustration'));

    await setValues({});
    final carried =
        (await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf)).sections.single;
    expect(carried.band(mosy1, NlaBand.glr).total, 3); // A 90%, B 75%, F 90% carried
    expect(carried.band(mosy1, NlaBand.ld3Frustration).total, 0);
    expect(carried.assessed(mosy1).total, 5); // E has no comprehension: no band
  });

  test('band trend follows values_form2b', () async {
    Future<num?> ld3Mosy1() async {
      final chart = await t.trendVm.bandDistribution(const SectionScope(_sec), _year, asOf: _asOf);
      final i = chart.xLabels.indexOf(mosy1.label);
      return chart.series.singleWhere((x) => x.name == NlaBand.ld3Frustration.label).values[i];
    }

    await setValues({});
    expect(await ld3Mosy1(), 0);
    await setValues({PhilIriValueList.form2b: PhilIriValues.actual});
    expect(await ld3Mosy1(), 4);
  });

  test('SRP, actual: no EOSY reading = not assessed, ranked first; D (EOSY 90%) not listed', () async {
    await setValues({PhilIriValueList.srp: PhilIriValues.actual});
    final srp = await t.srpVm.candidates(schoolId: 1, schoolYear: _year, sectionIds: {_sec}, asOf: _asOf);
    expect(srp.values, PhilIriValues.actual);
    final list = srp.sections.single.candidates;
    expect(list.map((x) => x.student.id).toSet(), {a, b, c, e, f});
    for (final x in list) {
      expect((x.notAssessed, x.rank, x.levelsDown, x.basisRound), (true, 1, 3, null), reason: '${x.student.id}');
    }
    expect(norm(srpListCsv(srp)).split('\n')[1], endsWith(',yes,actual'));
  });

  test('ARAL proposals, actual: a GST-only BOSY is the stand-in', () async {
    await setValues({PhilIriValueList.aral: PhilIriValues.actual});
    final prop = {for (final x in await t.aralVm.propose(sectionId: _sec, schoolYear: _year)) x.student.id: x};
    final pb = prop[b]!;
    expect(pb.status, AralCandidateStatus.proposed);
    expect(pb.reason, 'Not assessed this round (actual values): counted as Struggling, 3 levels down (Grade 4)');
    expect((pb.basisLevel, pb.basisRound, pb.basisAssessmentId), ('not_assessed', 'bosy', null));
    expect((pb.rankKey!.wordRecognition, pb.rankKey!.comprehension, pb.rankKey!.speed), (0, 0, 0));
    expect(pb.rank, 1);
    // C read at BOSY: the same proposal under both values.
    await setValues({});
    final carriedC = (await t.aralVm.propose(sectionId: _sec, schoolYear: _year)).singleWhere((x) => x.student.id == c);
    expect(prop[c]!.reason, carriedC.reason);
  });

  test('ARAL report and updates, actual: F judged on MOSY 2 own reading; carried exits F', () async {
    await setValues({PhilIriValueList.aral: PhilIriValues.actual});
    final rep = await adm.aralReportVm.implementationReport(schoolId: 1, schoolYear: _year, asOf: _asOf);
    expect(rep.values, PhilIriValues.actual);
    final row = rep.rows.firstWhere((x) => x.section.id == _sec);
    expect(row.mosyTotal, 1);
    expect(row.mosy.containsKey('GLR'), isFalse); // MOSY 2 own 20%, not the carried 90%
    expect(norm(await adm.aralReportVm.implementationReportCsv(schoolId: 1, schoolYear: _year, asOf: _asOf))
        .split('\n')[1], endsWith(',actual'));

    final actual = (await t.aralVm.applyResults(sectionId: _sec, schoolYear: _year)).first;
    expect(actual.after.isActive, isTrue);
    expect(actual.reason, startsWith('Phil-IRI MOSY #2 (actual) ('));

    await setValues({});
    final carriedRep = await adm.aralReportVm.implementationReport(schoolId: 1, schoolYear: _year, asOf: _asOf);
    expect(carriedRep.rows.firstWhere((x) => x.section.id == _sec).mosy['GLR'], 1);
    final carried = (await t.aralVm.applyResults(sectionId: _sec, schoolYear: _year)).first;
    expect(carried.kind, AralUpdateKind.exited);
    expect(carried.reason, startsWith('Phil-IRI MOSY #2 ('));
    expect(carried.reason, isNot(contains('(actual)')));
  });
}
