// aral-class-progress (spec docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md D4).
import 'dart:io';

import 'package:basa_capstone/core/console/commands/aral_class_commands.dart';
import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/offline_owner.dart';

const _year = '2026-2027';

void main() {
  late ConsoleRegistry r;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_progress_cmd_').path);
    final t = wireTutor(ctx, wireShared(ctx));
    r = ConsoleRegistry();
    registerAralClassCommands(r, t.aralClassVm, t.aralVm);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZPC1', 'school_name': 'ZZ Progress cmd', 'region_id': 13});
    await db.insert('sections', {'id': 71, 'school_id': 1, 'school_year': _year, 'grade_level': '2', 'section_name': 'S71'});
    await db.insert('students', {'id': 1, 'lrn': '999900000201', 'last_name': 'Cruz', 'first_name': 'Ana', 'school_id': 1});
    await db.insert('enrollments', {'student_id': 1, 'section_id': 71, 'school_year': _year, 'status': 'active'});
    await db.insert('aral_classes', {'id': 1, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-G2-01',
        'grade_level': 2, 'origin': 'cloud', 'row_version': 1});
    await db.insert('aral_enrollments', {
      'id': 1, 'student_id': 1, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'key_stage': 'ks1',
      'class_id': 1, 'status': 'active', 'entered_on': '2026-07-01', 'basis_source': 'crla', 'basis_round': 'bosy',
      'basis_level': 'x', 'origin': 'cloud', 'row_version': 1,
    });
    for (final (id, round, day, profile) in [
      (101, 'bosy', '2026-08-03', 'Low Emerging Reader'),
      (102, 'mosy', '2026-10-05', 'Developing Reader'),
    ]) {
      await db.insert('crla_assessments', {
        'id': id, 'student_id': 1, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'subject_variant': 'fil',
        'language': 'Tagalog', 'round': round, 'attempt_no': id - 100, 'assessed_at': day, 'origin': 'cloud',
        'row_version': 1, 'reading_profile': profile,
      });
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000pc', email: 'pc@test', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'pc@test', password: 'test-pw'), isNull);
  });

  test('one line per learner: start -> latest and the change', () async {
    expect(await r.execute('aral-class-progress 1 asof=2026-11-27'),
        'ARAL-R-G2-01: 1 learner\n'
        'CRUZ, Ana | Grade 2 CRLA | BOSY Low Emerging Reader -> MOSY Developing Reader | Up');
  });

  test('before the MOSY attempt: not assessed yet', () async {
    expect(await r.execute('aral-class-progress 1 asof=2026-09-01'),
        contains('CRUZ, Ana | Grade 2 CRLA | BOSY Low Emerging Reader -> - | Not assessed yet'));
  });

  test('a bad date and a bad usage are refused', () async {
    expect(await r.execute('aral-class-progress 1 asof=2026-02-30'),
        'asof must be a real YYYY-MM-DD date (got "2026-02-30")');
    expect(await r.execute('aral-class-progress'), 'Usage: aral-class-progress <classId> [asof=YYYY-MM-DD]');
  });
}
