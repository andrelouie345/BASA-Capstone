// Remove buttons for work not uploaded yet (owner 2026-11-15): the CRLA
// attempt screen offers Remove only for an attempt on this device alone; the
// GST list only on each learner's latest GST on this device alone. Both ask
// first, with the warning.
import 'dart:io';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/common/screen_kit.dart' show removeUnsentWarning;
import 'package:basa_capstone/ui/crla/crla_entry_screen.dart';
import 'package:basa_capstone/ui/phil_iri/gst_screen.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppViewModels vms;
  var seeded = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> seed() async {
    if (seeded) return;
    seeded = true;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_remove_ui_').path);
    final shared = wireShared(ctx);
    vms = appViewModels(ctx, shared, wireTutor(ctx, shared));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 9501, 'school_id': 'ZZRB1', 'school_name': 'ZZ Remove UI', 'region_id': 13});
    for (final (id, grade) in [(9501, '2'), (9502, '5')]) {
      await db.insert('sections', {'id': id, 'school_id': 9501, 'school_year': _year, 'grade_level': grade,
          'section_name': 'S$id'});
      await db.insert('students', {'id': id, 'lrn': '9999999995$id', 'last_name': 'ZZRB', 'first_name': 'L$id',
          'school_id': 9501});
      await db.insert('enrollments', {'student_id': id, 'section_id': id, 'school_year': _year, 'status': 'active'});
    }
    // An uploaded attempt (positive id) has no Remove.
    await db.insert('crla_assessments', {
      'id': 9501, 'student_id': 9501, 'school_id': 9501, 'section_id': 9501, 'school_year': _year,
      'subject_variant': 'eng', 'language': 'English', 'round': 'bosy', 'attempt_no': 1,
      'assessed_at': '2026-08-10', 'origin': 'cloud', 'row_version': 1,
    });
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000rb01', email: 'rb@test', role: 'tutor',
        schoolId: 9501);
    expect(await ctx.authVm.signInOffline(email: 'rb@test', password: 'test-pw'), isNull);
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    await tester.pumpWidget(BasaScope(
      vms: vms,
      child: MaterialApp(theme: basaThemeData(Brightness.light), home: home),
    ));
    await _settle(tester);
  }

  testWidgets('CRLA: Remove only on an attempt not uploaded; it asks, then removes', (tester) async {
    await tester.runAsync(seed);
    await show(tester, const CrlaEntryScreen(assessmentId: 9501));
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    late int id;
    await tester.runAsync(() async => id = (await vms.crla.startAssessment(
            studentId: 9501, sectionId: 9501, schoolYear: _year, subjectVariant: 'fil', round: CrlaRound.bosy))
        .id!);
    await tester.pumpWidget(const SizedBox()); // a fresh screen, as opening it from the list does
    await show(tester, CrlaEntryScreen(assessmentId: id));
    expect(find.text('Not uploaded yet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await _settle(tester);
    expect(find.textContaining(removeUnsentWarning), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await _settle(tester);
    late Object? gone;
    await tester.runAsync(() async => gone = await vms.crla.getAssessment(id));
    expect(gone, isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets("GST: Remove only on the learner's latest score not uploaded", (tester) async {
    await tester.runAsync(seed);
    await tester.runAsync(() async {
      for (final score in [5, 15]) {
        await vms.philIri.recordGst(studentId: 9502, sectionId: 9502, schoolYear: _year, totalScore: score);
      }
    });
    await show(tester, const GstScreen());
    await tester.tap(find.text('Section').last);
    await _settle(tester);
    await tester.tap(find.text('Grade 5 · S9502 ($_year)').last);
    await _settle(tester);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await _settle(tester);
    expect(find.textContaining('15/20'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await _settle(tester);
    // The 15 is gone; the 5 is now the latest and can go too.
    expect(find.textContaining('15/20'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
