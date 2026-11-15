// test/ui/phil_iri_ranking_screen_test.dart
// The Phil-IRI ranking screen (docs/handoff/screens/value-sources.md#ranking-list):
// a coordinator ranks the whole school at BOSY by comprehension. One Grade 7
// learner read at BOSY (2/2 = 100%) is ranked; one with no reading is in the
// "Not ranked" block with its reason; the list says which values it uses
// (ranking default = actual). Nothing runs before the Rank button.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/admin/phil_iri_ranking_screen.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/admin_viewmodels.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _section = 93;
const _read = 721, _notRead = 722;

late AppViewModels _vms;
late AdminViewModels _admin;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= 5 && find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('rank the school at BOSY by comprehension: ranked, not ranked, values label', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('basa_ranking_ui_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
      final ctx = await AppContext.open(dataDir: '${dir.path}${Platform.pathSeparator}data');
      final shared = wireShared(ctx);
      final tutor = wireTutor(ctx, shared);
      _admin = adminViewModels(await wireAdmin(ctx, shared, tutor));
      _vms = appViewModels(ctx, shared, tutor);
      final db = ctx.localDb;
      await db.insert('schools', {'id': 1, 'school_id': 'ZZ45', 'school_name': 'ZZ ranking'});
      await seedOfflineOwner(db,
          userId: '00000000-0000-0000-0000-00000000ab47', email: 'rank@test', role: 'coordinator', schoolId: 1);
      await db.insert('sections',
          {'id': _section, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S93'});
      for (final (id, last) in [(_read, 'Alpha'), (_notRead, 'Bravo')]) {
        await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': last, 'first_name': 'F', 'school_id': 1});
        await db.insert('enrollments', {'student_id': id, 'section_id': _section, 'school_year': _year, 'status': 'active'});
      }
      await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded', 'is_grade_leveled': 1, 'has_comprehension': 1});
      await db.insert('phil_iri_passages', {
        'id': 501, 'collection_id': 1, 'level': 7, 'title': 'P501',
        'body': List.filled(120, 'w').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (final q in [1, 2]) {
        await db.insert('phil_iri_questions', {
          'id': 5010 + q, 'passage_id': 501, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a',
        });
      }
      expect(await ctx.authVm.signInOffline(email: 'rank@test', password: 'test-pw'), isNull);
      final vm = tutor.philIriVm;
      final s = await vm.startSession(
          studentId: _read, sectionId: _section, schoolYear: _year, round: PhilIriRound.bosy, assessedAt: DateTime(2026, 8, 5));
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: 501, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      await vm.answer(readingId: r.id!, questionId: 5011, chosen: 'a');
      await vm.answer(readingId: r.id!, questionId: 5012, chosen: 'a');
      await vm.complete(s.id!);
    });

    await tester.binding.setSurfaceSize(const Size(1300, 2000));
    await tester.pumpWidget(AdminScope(
      vms: _admin,
      child: BasaScope(vms: _vms, child: MaterialApp(theme: basaThemeData(Brightness.light), home: const PhilIriRankingScreen())),
    ));
    await _settle(tester);

    // Nothing ranked before the button.
    expect(find.text('Set the round, measure and scope, then Rank.'), findsOneWidget);
    await tester.tap(find.text('Rank'));
    await _settle(tester);

    expect(find.textContaining('BOSY · Comprehension % · whole school (Grades 4-10) · lowest 10'), findsOneWidget);
    expect(find.text(philIriValuesLabel(PhilIriValues.actual)), findsOneWidget);
    // Block 1: the learner who read, 2/2.
    expect(find.text('Alpha, F'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    // Block 2: no BOSY reading, with the reason.
    expect(find.text('Not ranked'), findsOneWidget);
    expect(find.text('Bravo, F'), findsOneWidget);
    expect(find.text('not assessed this round'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
