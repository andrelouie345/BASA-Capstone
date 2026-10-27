// test/ui/screens_data_test.dart
// The screens with data on the device: a school, a Grade 2 and a Grade 5
// section with learners, and an ARAL class with two learners. Picks a
// section (or opens a learner / class directly) and checks the lists show
// what is saved, without exceptions or overflow, at phone size.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/admin/aral_editing.dart';
import 'package:basa_capstone/ui/aral/classes_screen.dart';
import 'package:basa_capstone/ui/aral/learner_aral_screen.dart';
import 'package:basa_capstone/ui/aral/roster_screen.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/crla/crla_section_screen.dart';
import 'package:basa_capstone/ui/learners/learners_screen.dart';
import 'package:basa_capstone/ui/learners/sections_screen.dart';
import 'package:basa_capstone/ui/phil_iri/gst_screen.dart';
import 'package:basa_capstone/ui/phil_iri/phil_iri_section_screen.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/admin_viewmodels.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';

late AppViewModels _vms;
late AdminViewModels _admin;
late int _classId;
late int _enrollmentId;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(AdminScope(
    vms: _admin,
    child: BasaScope(vms: _vms, child: MaterialApp(theme: basaThemeData(Brightness.light), home: screen)),
  ));
  await _settle(tester);
}

/// Opens the dropdown labelled [label] and picks the item showing [item].
Future<void> _pick(WidgetTester tester, String label, String item) async {
  await tester.tap(find.text(label).last);
  await _settle(tester);
  await tester.tap(find.text(item).last);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // LocalDatabase.instance is one per process: seed the device once, the
  // first test that asks (testWidgets runs in fake async: real IO in runAsync).
  var seeded = false;
  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    if (seeded) return;
    seeded = true;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_data_ui_').path);
    final shared = wireShared(ctx);
    final tutor = wireTutor(ctx, shared);
    _admin = adminViewModels(await wireAdmin(ctx, shared, tutor));
    _vms = appViewModels(ctx, shared, tutor);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZUI', 'school_name': 'ZZ UI School'});
    await db.insert('sections', {'id': 1, 'school_id': 1, 'school_year': _year, 'grade_level': '2', 'section_name': 'Rose'});
    await db.insert('sections', {'id': 2, 'school_id': 1, 'school_year': _year, 'grade_level': '5', 'section_name': 'Lily'});
    for (final (id, section, last) in [(1, 1, 'Santos'), (2, 1, 'Reyes'), (3, 2, 'Cruz'), (4, 2, 'Bautista')]) {
      await db.insert('students', {'id': id, 'lrn': '12345678900$id', 'last_name': last, 'first_name': 'Ana', 'sex': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    }
    Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
    _classId = await localId();
    await db.insert('aral_classes', {'id': _classId, 'school_id': 1, 'school_year': _year, 'class_name': 'Sampaguita', 'grade_level': 5});
    for (final student in [3, 4]) {
      final id = await localId();
      if (student == 3) _enrollmentId = id;
      await db.insert('aral_enrollments', {
        'id': id, 'student_id': student, 'school_id': 1, 'section_id': 2, 'school_year': _year,
        'key_stage': 'ks2', 'track': 'basic', 'entered_on': '2026-10-01', 'basis_source': 'manual', 'class_id': _classId,
      });
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000ad03', email: 'coord@test', role: 'coordinator', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'coord@test', password: 'test-pw'), isNull);
  });

  testWidgets('sections and learners', (tester) async {
    await seed(tester);
    await _show(tester, const SectionsScreen());
    expect(find.text('Rose'), findsOneWidget);
    expect(find.text('Lily'), findsOneWidget);

    await _show(tester, const LearnersScreen());
    await _pick(tester, 'Section', 'Grade 2 · Rose ($_year)');
    expect(find.textContaining('Santos'), findsOneWidget);
    expect(find.textContaining('Reyes'), findsOneWidget);
    expect(find.textContaining('Cruz'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CRLA lists only Grades 1-3 and shows the section', (tester) async {
    await seed(tester);
    await _show(tester, const CrlaSectionScreen());
    await _pick(tester, 'Section', 'Grade 2 · Rose ($_year)');
    expect(find.text('Start an attempt'), findsOneWidget);
    expect(find.text('No CRLA attempts in this section yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phil-IRI section and GST show the Grade 5 learners', (tester) async {
    await seed(tester);
    await _show(tester, const PhilIriSectionScreen());
    await _pick(tester, 'Section', 'Grade 5 · Lily ($_year)');
    expect(find.textContaining('Cruz'), findsOneWidget);
    expect(find.textContaining('Bautista'), findsOneWidget);

    await _show(tester, const GstScreen());
    await _pick(tester, 'Section', 'Grade 5 · Lily ($_year)');
    expect(find.text('Record a score'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ARAL roster, class and a learner page', (tester) async {
    await seed(tester);
    await _show(tester, const AralRosterScreen(editor: AdminAralRosterEditor()));
    await _pick(tester, 'Section', 'Grade 5 · Lily ($_year)');
    expect(find.textContaining('Cruz'), findsOneWidget);
    expect(find.textContaining('KS2 Basic'), findsWidgets);

    await _show(tester, AralClassScreen(classId: _classId, editor: const AdminAralClassEditor()));
    expect(find.text('Sampaguita'), findsOneWidget);
    expect(find.textContaining('Bautista'), findsOneWidget);

    await _show(tester, LearnerAralScreen(enrollmentId: _enrollmentId, name: 'Cruz, Ana'));
    expect(find.text('Attendance'), findsWidgets);
    for (final tab in ['IRIP', 'Check-ins', 'Materials', 'Readability']) {
      await tester.tap(find.text(tab));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
