// Removing work started by mistake (owner 2026-11-15): a CRLA attempt (with
// its parts) or a GST result, only while it is on this device alone (not
// uploaded, not waiting in an upload) and only the learner's latest one.
import 'dart:io';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/crla_viewmodel.dart';
import 'package:basa_capstone/viewmodels/phil_iri_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9601, _g2 = 9601, _g5 = 9602, _crlaLearner = 9601, _gstLearner = 9602;
const _year = '2026-2027';

Matcher _refused(Object message) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late AppContext ctx;
  late CrlaViewModel crla;
  late PhilIriViewModel philIri;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_remove_unsent_').path);
    final t = wireTutor(ctx, wireShared(ctx));
    crla = t.crlaVm;
    philIri = t.philIriVm;
    final db = ctx.localDb;
    await db.insert('schools', {'id': _school, 'school_id': 'ZZRU1', 'school_name': 'ZZ Remove', 'region_id': 13});
    for (final (id, grade) in [(_g2, '2'), (_g5, '5')]) {
      await db.insert('sections', {'id': id, 'school_id': _school, 'school_year': _year, 'grade_level': grade,
          'section_name': 'S$id'});
    }
    for (final (id, section) in [(_crlaLearner, _g2), (_gstLearner, _g5)]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'ZZRU', 'first_name': 'L$id',
          'school_id': _school});
      await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000ru01', email: 'ru@test', role: 'tutor',
        schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'ru@test', password: 'test-pw'), isNull);
  });

  Future<int> start() async => (await crla.startAssessment(
          studentId: _crlaLearner, sectionId: _g2, schoolYear: _year, subjectVariant: 'fil', round: CrlaRound.bosy))
      .id!;

  Future<int> parts(int id) async {
    final rows = await ctx.localDb.rawQuery(
        'SELECT (SELECT COUNT(*) FROM crla_part1_standard WHERE assessment_id = ?) + '
        '(SELECT COUNT(*) FROM crla_part2_fluency WHERE assessment_id = ?) AS n',
        [id, id]);
    return rows.first['n'] as int;
  }

  test('CRLA: only the latest attempt, with its parts; then the one before it', () async {
    final first = await start();
    final second = await start();
    await crla.savePart1Standard(assessmentId: second, task1Score: 8, task2HighScore: 9);
    expect(await parts(second), 1);

    await expectLater(crla.removeAttempt(first),
        _refused('Only the latest attempt can be removed: this is attempt 1, attempt 2 of this test is newer.'));
    await crla.removeAttempt(second);
    expect(await crla.getAssessment(second), isNull);
    expect(await parts(second), 0);
    await crla.removeAttempt(first);
    expect(await crla.getAssessment(first), isNull);
  });

  test('CRLA: refused while waiting in an upload (nothing removed)', () async {
    final id = await start();
    await crla.savePart1Standard(assessmentId: id, task1Score: 8, task2HighScore: 9);
    await ctx.localDb.insert('sync_pending', {'table_name': 'crla_assessments', 'row_key': '$id', 'upload_id': 1});
    await expectLater(
        crla.removeAttempt(id), _refused('This record is waiting for approval. Withdraw the upload to change it.'));
    expect(await crla.getAssessment(id), isNotNull);
    expect(await parts(id), 1);
    await ctx.localDb.delete('sync_pending', where: 'row_key = ?', whereArgs: ['$id']);
    await crla.removeAttempt(id);
  });

  test('CRLA: refused while an ARAL roster entry uses it', () async {
    final id = await start();
    await ctx.localDb.insert('aral_enrollments', {
      'id': 9601, 'student_id': _crlaLearner, 'school_id': _school, 'section_id': _g2, 'school_year': _year,
      'key_stage': 'ks1', 'entered_on': '2026-08-20', 'basis_source': 'crla', 'basis_level': 'Low Emerging Reader', 'basis_assessment_id': id,
      'origin': 'cloud', 'row_version': 1,
    });
    await expectLater(crla.removeAttempt(id),
        _refused('An ARAL roster entry uses this attempt. Remove or change that entry first.'));
    await ctx.localDb.delete('aral_enrollments', where: 'id = 9601');
    await crla.removeAttempt(id);
  });

  test('CRLA: an uploaded attempt stays; an unknown id is refused', () async {
    await ctx.localDb.insert('crla_assessments', {
      'id': 9601, 'student_id': _crlaLearner, 'school_id': _school, 'section_id': _g2, 'school_year': _year,
      'subject_variant': 'eng', 'language': 'English', 'round': 'bosy', 'attempt_no': 1,
      'assessed_at': '2026-08-10', 'origin': 'cloud', 'row_version': 1,
    });
    await expectLater(crla.removeAttempt(9601), _refused(crlaRemoveUploadedMessage));
    await expectLater(crla.removeAttempt(-999999), _refused('This CRLA attempt is not on this device. Download the latest data, then try again.'));
  });

  test('GST: only the latest; an uploaded one stays', () async {
    Future<int> record(int score) async =>
        (await philIri.recordGst(studentId: _gstLearner, sectionId: _g5, schoolYear: _year, totalScore: score)).id!;
    final first = await record(5);
    final second = await record(15);
    await expectLater(
        philIri.removeGst(first), _refused('Only the latest GST can be removed: this is attempt 1, attempt 2 is newer.'));
    await philIri.removeGst(second);
    await philIri.removeGst(first);
    expect(await philIri.gstForSection(_g5, schoolYear: _year), isEmpty);

    await ctx.localDb.insert('phil_iri_gst_results', {
      'id': 9601, 'student_id': _gstLearner, 'school_id': _school, 'section_id': _g5, 'school_year': _year,
      'max_score': 20, 'total_score': 12, 'attempt_no': 1, 'taken_at': '2026-08-10', 'origin': 'cloud',
      'row_version': 1,
    });
    await expectLater(philIri.removeGst(9601), _refused(philIriGstRemoveUploadedMessage));
    await expectLater(philIri.removeGst(-999999), _refused('This GST score is not on this device. Download the latest data, then try again.'));
  });
}
