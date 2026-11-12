// test/ui/phil_iri_import_screen_test.dart
// The Phil-IRI import screen (docs/handoff/screens/phil-iri-import.md) with a
// made-up VNHS ARAL workbook (GST scores only, so no passages are needed):
// preview, search and the "Needs a pick" filter, a learner pick and the BOSY
// date, the import and its result; a header issue opens the headers step; the
// scoresheet mode saves a section's template.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/admin/phil_iri_import_screen.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/admin_viewmodels.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';
import '../helpers/phil_iri_workbook_fixture.dart';

const _year = '2026-2027';

late AppViewModels _vms;
late AdminViewModels _admin;
late Directory _dir;

/// Lets real IO run (database, files) until the screen is not busy any more.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= 5 && find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
}

Future<void> _show(WidgetTester tester, Widget screen, {Size size = const Size(400, 860)}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(AdminScope(
    vms: _admin,
    child: BasaScope(vms: _vms, child: MaterialApp(theme: basaThemeData(Brightness.light), home: screen)),
  ));
  await _settle(tester);
}

/// Writes a made-up workbook of section IRON (Grade 7): three GSTs; two
/// learners named "SANTOS, ANA" in BASA, so that row needs a pick.
String _workbook(String name, {Map<String, String> renames = const {}}) {
  final path = '${_dir.path}${Platform.pathSeparator}$name.xlsx';
  File(path).writeAsBytesSync(buildPhilIriWorkbook([
    WbSheet('01',
        section: 'IRON',
        schoolYear: _year,
        males: const [WbLearner('REYES, BEN', gst: 25)],
        females: const [WbLearner('CRUZ, ANA', gst: 30), WbLearner('SANTOS, ANA', gst: 20)],
        renames: renames),
  ]));
  return path;
}

Future<void> _preview(WidgetTester tester, String path) async {
  await tester.enterText(find.byKey(const Key('philIriImport.path')), path);
  await tester.tap(find.byKey(const Key('philIriImport.preview')));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // LocalDatabase.instance is one per process: seed the device once.
  var seeded = false;
  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    if (seeded) return;
    seeded = true;
    _dir = Directory.systemTemp.createTempSync('basa_pi_import_ui_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => _dir.path,
    );
    final ctx = await AppContext.open(dataDir: '${_dir.path}${Platform.pathSeparator}data');
    final shared = wireShared(ctx);
    final tutor = wireTutor(ctx, shared);
    _admin = adminViewModels(await wireAdmin(ctx, shared, tutor));
    _vms = appViewModels(ctx, shared, tutor);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': '303988', 'school_name': 'ZZ VNHS'});
    await db.insert('sections', {'id': 1, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'IRON'});
    for (final (id, last, first, sex) in [
      (1, 'Cruz', 'Ana', 'F'),
      (2, 'Reyes', 'Ben', 'M'),
      (3, 'Santos', 'Ana', 'F'),
      (4, 'Santos', 'Ana', 'F'),
    ]) {
      await db.insert('students', {'id': id, 'lrn': '40000000000$id', 'last_name': last, 'first_name': first, 'sex': sex, 'school_id': 1});
      await db.insert('enrollments', {'student_id': id, 'section_id': 1, 'school_year': _year, 'status': 'active'});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000ad07', email: 'coord@test', role: 'coordinator', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'coord@test', password: 'test-pw'), isNull);
  });

  testWidgets('workbook: preview, search, needs-a-pick filter, pick, date, import', (tester) async {
    await seed(tester);
    final path = await tester.runAsync(() async => _workbook('wb_ok'));
    await _show(tester, const PhilIriImportScreen());
    expect(find.text('VNHS ARAL workbook (v26.0531–v26.1130)'), findsOneWidget);

    await _preview(tester, path!);
    expect(find.textContaining('Sheet 01'), findsWidgets);
    expect(find.text('importable'), findsOneWidget);
    // A card starts closed; its rows open on request.
    expect(find.textContaining('REYES, BEN'), findsNothing);
    await tester.tap(find.text('Show 3 row(s)'));
    await _settle(tester);
    expect(find.textContaining('REYES, BEN'), findsOneWidget);
    expect(find.textContaining('CRUZ, ANA'), findsOneWidget);

    // Search: only Reyes' row is left.
    await tester.enterText(find.byKey(const Key('philIriImport.search')), 'reyes');
    await _settle(tester);
    expect(find.textContaining('REYES, BEN'), findsOneWidget);
    expect(find.textContaining('CRUZ, ANA'), findsNothing);
    expect(find.text('1 of 3 rows'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('philIriImport.search')), '');
    await _settle(tester);

    // Show: Needs a pick -> only the Santos row (two BASA learners of that name).
    await tester.ensureVisible(find.byKey(const Key('philIriImport.show')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('philIriImport.show')));
    await _settle(tester);
    await tester.tap(find.text('Needs a pick').last);
    await _settle(tester);
    expect(find.textContaining('SANTOS, ANA'), findsOneWidget);
    expect(find.textContaining('REYES, BEN'), findsNothing);

    // Pick the first Santos for that row (females start at row 18: Cruz 18,
    // Santos 19): the preview runs again.
    expect(find.byKey(const Key('philIriImport.pick.sheet 01, row 19')), findsOneWidget);
    await tester.ensureVisible(find.text('Skip (not imported)').last);
    await tester.pump();
    await tester.tap(find.text('Skip (not imported)').last);
    await _settle(tester);
    await tester.tap(find.textContaining('Santos, Ana').last);
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('philIriImport.show')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('philIriImport.show')));
    await _settle(tester);
    await tester.tap(find.text('All').last);
    await _settle(tester);

    // No calendar here: the BOSY date (GST) is picked (today).
    expect(find.byKey(Key('philIriImport.date.${PhilIriRound.bosy.name}')), findsOneWidget);
    await tester.ensureVisible(find.byKey(Key('philIriImport.date.${PhilIriRound.bosy.name}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('philIriImport.date.${PhilIriRound.bosy.name}')));
    await _settle(tester);
    await tester.tap(find.text('OK'));
    await _settle(tester);

    // Tick the sheet; the one-time warning sits above the button.
    await tester.ensureVisible(find.byKey(const Key('philIriImport.tick.01')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('philIriImport.tick.01')));
    await _settle(tester);
    expect(find.textContaining("You can't import this section's workbook again."), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('philIriImport.import')));
    await tester.tap(find.byKey(const Key('philIriImport.import')));
    await _settle(tester);
    expect(find.textContaining('3 GST result(s)'), findsOneWidget);
    expect(find.text('Send my work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a renamed header opens the headers step', (tester) async {
    await seed(tester);
    final path = await tester.runAsync(() async => _workbook('wb_headers', renames: {'GST Raw Score': 'GST Score'}));
    await _show(tester, const PhilIriImportScreen());
    await _preview(tester, path!);
    expect(find.text('Column headers to check'), findsOneWidget);
    expect(find.textContaining('GST Raw Score'), findsWidgets);
    expect(find.text('Save and preview again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scoresheet mode: download the section template', (tester) async {
    await seed(tester);
    await _show(tester, const PhilIriImportScreen(scoresheet: true), size: const Size(1280, 800));
    await tester.tap(find.byKey(const Key('philIriImport.template')));
    await _settle(tester);
    final saved = File('${_dir.path}${Platform.pathSeparator}BASA${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}7_IRON_Phil-IRI_scoresheet.xlsx');
    expect(await tester.runAsync(saved.exists), isTrue);
    expect(tester.takeException(), isNull);
  });
}
