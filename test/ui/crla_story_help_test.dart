// The Part 2 form's story list and the "Story number and words read" help
// page (2026-11-15): the attempt's stories under the story number field, the
// no-story-list wording, the "?" opening the help page over the form.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/crla/crla_entry_screen.dart';
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
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_story_ui_').path);
    final shared = wireShared(ctx);
    vms = appViewModels(ctx, shared, wireTutor(ctx, shared));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 9701, 'school_id': 'ZZSH1', 'school_name': 'ZZ Stories', 'region_id': 13});
    await db.insert('sections', {'id': 9701, 'school_id': 9701, 'school_year': _year, 'grade_level': '2',
        'section_name': 'S1'});
    await db.insert('students', {'id': 9701, 'lrn': '999999997701', 'last_name': 'ZZSH', 'first_name': 'One',
        'school_id': 9701});
    for (final (id, language) in [(9701, 'Tagalog'), (9702, 'Cebuano')]) {
      await db.insert('crla_assessments', {
        'id': id, 'student_id': 9701, 'school_id': 9701, 'section_id': 9701, 'school_year': _year,
        'subject_variant': language == 'Tagalog' ? 'fil' : 'mt', 'language': language, 'round': 'bosy',
        'attempt_no': 1, 'assessed_at': '2026-08-10', 'origin': 'cloud', 'row_version': 1,
      });
    }
    for (final (id, no, title, words) in [(9701, 1, 'Ang Una', 96), (9702, 2, 'Ang Ikalawa', 80)]) {
      await db.insert('crla_stories', {'id': id, 'region_id': 13, 'language': 'Tagalog', 'grade': 2,
          'story_no': no, 'title': title, 'word_count': words});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000sh01', email: 'sh@test', role: 'tutor',
        schoolId: 9701);
    expect(await ctx.authVm.signInOffline(email: 'sh@test', password: 'test-pw'), isNull);
  }

  Future<void> show(WidgetTester tester, int assessmentId) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    await tester.pumpWidget(BasaScope(
      vms: vms,
      child: MaterialApp(theme: basaThemeData(Brightness.light), home: CrlaEntryScreen(assessmentId: assessmentId)),
    ));
    await _settle(tester);
  }

  Future<void> openPart2(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Enter').last);
    await _settle(tester);
  }

  testWidgets('the Part 2 form lists the stories; "?" opens the help page', (tester) async {
    await tester.runAsync(seed);
    await show(tester, 9701);
    await openPart2(tester);
    expect(find.textContaining('1 · Ang Una (96 words)'), findsOneWidget);
    expect(find.textContaining('2 · Ang Ikalawa (80 words)'), findsOneWidget);
    expect(find.textContaining('Ask your coordinator'), findsOneWidget);
    expect(find.textContaining('Leave blank'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.help_outline)));
    await _settle(tester);
    expect(find.text('Story number and words read'), findsOneWidget);
    expect(find.textContaining('Coordinators tell tutors which story number to use'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('no story list: the form says so and asks for words read', (tester) async {
    await tester.runAsync(seed);
    await show(tester, 9702);
    await openPart2(tester);
    expect(find.textContaining('No story list for this region, language and grade'), findsOneWidget);
    expect(find.textContaining("Needed here: the story's total words"), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
