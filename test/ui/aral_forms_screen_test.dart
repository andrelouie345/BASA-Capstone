// test/ui/aral_forms_screen_test.dart
// The ARAL Forms 1, 2 and 4 screen (admin build) at phone size: Form 1 and
// Form 2 saved as .xlsx in the export folder, their notes shown on the
// screen, the Form 1 class choice, and no overflow.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/admin/aral_forms_screen.dart';
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

/// Waits (real time) until [finder] shows, up to about 15 seconds.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('save Form 1 (one class) and Form 2; their notes show', (tester) async {
    late AppViewModels vms;
    late AdminViewModels admin;
    late String exports;
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('basa_forms_ui_');
      exports = '${dir.path}${Platform.pathSeparator}BASA${Platform.pathSeparator}exports';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
      final ctx = await AppContext.open(dataDir: '${dir.path}${Platform.pathSeparator}data');
      final shared = wireShared(ctx);
      final tutor = wireTutor(ctx, shared);
      admin = adminViewModels(await wireAdmin(ctx, shared, tutor));
      vms = appViewModels(ctx, shared, tutor);
      final db = ctx.localDb;
      await db.insert('schools', {'id': 1, 'school_id': 'ZZF9', 'school_name': 'ZZ Forms UI'});
      await seedOfflineOwner(db,
          userId: '00000000-0000-0000-0000-00000000f0f1', email: 'forms@test', role: 'coordinator', schoolId: 1);
      await db.insert('sections', {'id': 1, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'Seven'});
      for (final (id, name) in [(-1, 'ARAL-R-G7-01'), (-2, 'ARAL-R-G7-02')]) {
        await db.insert('aral_classes',
            {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': name, 'grade_level': 7, 'session_type': 'pull_out'});
      }
      expect(await ctx.authVm.signInOffline(email: 'forms@test', password: 'test-pw'), isNull);
    });

    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(AdminScope(
      vms: admin,
      child: BasaScope(vms: vms, child: MaterialApp(theme: basaThemeData(Brightness.light), home: const AralFormsScreen())),
    ));
    await _settle(tester);
    expect(find.text('Form 1: class list'), findsOneWidget);
    expect(find.text('Every class'), findsOneWidget);

    // Form 1 for one class.
    await tester.tap(find.text('Every class'));
    await _settle(tester);
    await tester.tap(find.text('ARAL-R-G7-02').last);
    await _settle(tester);
    expect(find.text('ARAL-R-G7-02'), findsOneWidget); // the button shows the class
    await tester.tap(find.text('Save .xlsx').first);
    await _waitFor(tester, find.text('Saved'));
    expect(find.text('Saved'), findsOneWidget);
    expect(File('$exports${Platform.pathSeparator}ARAL_Form1_ARAL-R-G7-02_$_year.xlsx').existsSync(), isTrue);
    await tester.tap(find.text('Close').last);
    await _settle(tester);
    expect(find.textContaining('Left blank for hand entry: district, workbook issued'), findsOneWidget);

    // Form 2.
    await tester.ensureVisible(find.text('Save .xlsx').at(1));
    await _settle(tester);
    await tester.tap(find.text('Save .xlsx').at(1));
    await _waitFor(tester, find.text('Saved'));
    expect(File('$exports${Platform.pathSeparator}ARAL_Form2_$_year.xlsx').existsSync(), isTrue);
    await tester.tap(find.text('Close').last);
    await _settle(tester);
    expect(find.textContaining('Mathematics columns'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
