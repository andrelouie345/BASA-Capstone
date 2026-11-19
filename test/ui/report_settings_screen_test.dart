// test/ui/report_settings_screen_test.dart
// The Report settings screen (docs/handoff/screens/reports.md, value-sources.md,
// sf1-leavers.md *Archive period*): the archive period row and the six
// Phil-IRI carried/actual switches read from the device copy (region row +
// school row), and a save while signed in offline shows the ViewModel's
// online sign-in refusal and changes nothing.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/admin/report_screens.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/admin_viewmodels.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

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

/// The ListTile of the row titled [title].
Finder _row(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('archive period and value switches: region/school layers, offline save refused', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('basa_report_settings_ui_');
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
      await db.insert('schools', {'id': 1, 'school_id': '303988', 'school_name': 'ZZ VNHS'});
      // Region: Form 2b actual, archive 9 months. School: SRP actual, ranking carried, archive 3.
      await db.insert('report_settings', {
        'id': 1,
        'school_id': null,
        'settings': jsonEncode({'values_form2b': 'actual', 'archive_keep_months': 9}),
      });
      await db.insert('report_settings', {
        'id': 2,
        'school_id': 1,
        'settings': jsonEncode({'values_srp': 'actual', 'values_ranking': 'carried', 'archive_keep_months': 3}),
      });
      await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000ad08', email: 'coord@test', role: 'coordinator', schoolId: 1);
      expect(await ctx.authVm.signInOffline(email: 'coord@test', password: 'test-pw'), isNull);
    });

    await tester.binding.setSurfaceSize(const Size(500, 1800));
    await tester.pumpWidget(AdminScope(
      vms: _admin,
      child: BasaScope(vms: _vms, child: MaterialApp(theme: basaThemeData(Brightness.light), home: const ReportSettingsScreen())),
    ));
    await _settle(tester);

    // Archive period: the school's 3 applies over the region's 9.
    final archive = _row('Archive period (months)');
    expect(find.descendant(of: archive, matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: archive, matching: find.text('Region: 9 · School: 3')), findsOneWidget);

    expect(find.text('Phil-IRI values'), findsOneWidget);
    void expectRow(String title, String effective, String layers) {
      final row = _row(title);
      expect(find.descendant(of: row, matching: find.text(effective)), findsOneWidget, reason: title);
      expect(find.descendant(of: row, matching: find.text(layers)), findsOneWidget, reason: title);
    }

    // Nothing set: the default, actual since 2026-11-18.
    expectRow('ARAL (proposals, updates, implementation report)', 'Actual', 'Region: — · School: —');
    expectRow('BOSY masterlist', 'Actual', 'Region: — · School: —');
    expectRow('NLA report (Form 2b) and band trend', 'Actual', 'Region: actual · School: —');
    expectRow('SRP candidates', 'Actual', 'Region: — · School: actual');
    expectRow('Learner pages (Phil-IRI results, history)', 'Actual', 'Region: — · School: —');
    expectRow('Ranking list', 'Carried', 'Region: — · School: carried');

    // Saving needs an online sign-in: the refusal is shown and nothing changes.
    final ranking = _row('Ranking list');
    await tester.tap(find.descendant(of: ranking, matching: find.byIcon(Icons.edit)));
    await _settle(tester);
    await tester.tap(find.text("actual (each round's own reading)"));
    await _settle(tester);
    expect(find.text(needsOnlineSignInMessage), findsOneWidget);
    expectRow('Ranking list', 'Carried', 'Region: — · School: carried');
  });
}
