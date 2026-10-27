// test/ui/screens_smoke_test.dart
// Opens the home screen and every screen its navigation offers, with the
// real wiring and an empty device copy, signed in offline as an admin
// (admin build) and as a tutor (tutor build), at phone and desktop sizes.
// Fails on any exception or layout overflow while a screen builds and loads.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_home_sections.dart';
import 'package:basa_capstone/ui/admin/admin_scope.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/home/home_screen.dart';
import 'package:basa_capstone/ui/home/home_sections.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/admin_viewmodels.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _sizes = {'phone': Size(400, 860), 'desktop': Size(1280, 800)};

Widget _app(AppViewModels vms, AdminViewModels? admin, Widget home, Brightness b) {
  final app = BasaScope(
    vms: vms,
    child: MaterialApp(
      theme: basaThemeData(b),
      darkTheme: basaThemeData(Brightness.dark),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    ),
  );
  return admin == null ? app : AdminScope(vms: admin, child: app);
}

/// Lets the screen's real (sqlite) loads finish, frame by frame.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openAll(WidgetTester tester, AppViewModels vms, AdminViewModels? admin, List<HomeSection> sections) async {
  for (final size in _sizes.entries) {
    await tester.binding.setSurfaceSize(size.value);
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(_app(vms, admin, HomeScreen(title: 'BASA', sections: sections, onSignedOut: () {}), b));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'home, ${size.key}, $b');
    }
    for (final entry in sections.expand((s) => s.groups).expand((g) => g.entries)) {
      await tester.pumpWidget(_app(vms, admin, Builder(builder: entry.builder ?? (_) => NotBuiltScreen(entry: entry)), Brightness.light));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '${entry.title} (row ${entry.checklistRow}), ${size.key}');
      expect(find.byType(Scaffold), findsWidgets, reason: entry.title);
    }
  }
  await tester.binding.setSurfaceSize(null);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('admin build: home and every screen open', (tester) async {
    late AppViewModels vms;
    late AdminViewModels admin;
    await tester.runAsync(() async {
      final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_smoke_admin_').path);
      final shared = wireShared(ctx);
      final tutor = wireTutor(ctx, shared);
      admin = adminViewModels(await wireAdmin(ctx, shared, tutor));
      vms = appViewModels(ctx, shared, tutor);
      await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-00000000ad01', email: 'admin@test', role: 'admin', schoolId: 1);
      expect(await ctx.authVm.signInOffline(email: 'admin@test', password: 'test-pw'), isNull);
    });
    final sections = adminHomeSections();
    expect(sections.expand((s) => s.groups).expand((g) => g.entries).every((e) => e.builder != null), isTrue,
        reason: 'every admin entry has a screen');
    await _openAll(tester, vms, admin, sections);
  });

  testWidgets('tutor build: home and every screen open', (tester) async {
    late AppViewModels vms;
    await tester.runAsync(() async {
      final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_smoke_tutor_').path);
      final shared = wireShared(ctx);
      vms = appViewModels(ctx, shared, wireTutor(ctx, shared));
      await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-00000000ad02', email: 'tutor@test', role: 'tutor', schoolId: 1);
      expect(await ctx.authVm.signInOffline(email: 'tutor@test', password: 'test-pw'), isNull);
    });
    final sections = basaHomeSections();
    expect(sections.expand((s) => s.groups).expand((g) => g.entries).every((e) => e.builder != null), isTrue,
        reason: 'every tutor entry has a screen');
    await _openAll(tester, vms, null, sections);
  });
}
