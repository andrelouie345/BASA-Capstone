// test/ui/home_superadmin_only_test.dart
// HomeEntry.superadminOnly (2026-11-15, the cross-school transfers card,
// checklist row 64): the card is on the superadmin's home section and not
// on a school-bound admin's; a group left with no card shows no title.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/admin/admin_home_sections.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/home/home_screen.dart';
import 'package:basa_capstone/ui/home/home_sections.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _plain = HomeEntry(title: 'Plain card', description: '', icon: Icons.abc, checklistRow: 9001, doc: '');
const _super = HomeEntry(
    title: 'Super card', description: '', icon: Icons.abc, checklistRow: 9002, doc: '', superadminOnly: true);

final _sections = [
  const HomeSection(
    id: HomeSectionIds.home,
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    groups: [
      HomeGroup('Mixed', [_plain, _super]),
      HomeGroup('Super only group', [_super]),
    ],
  ),
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppViewModels> signedIn(int? schoolId) async {
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_home_super_').path);
    final shared = wireShared(ctx);
    final vms = appViewModels(ctx, shared, wireTutor(ctx, shared));
    await seedOfflineOwner(ctx.localDb,
        userId: '00000000-0000-0000-0000-0000000000${schoolId == null ? 'a1' : 'a2'}',
        email: 'admin@test',
        role: 'admin',
        schoolId: schoolId);
    expect(await ctx.authVm.signInOffline(email: 'admin@test', password: 'test-pw'), isNull);
    return vms;
  }

  Future<void> show(WidgetTester tester, AppViewModels vms) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    await tester.pumpWidget(BasaScope(
      vms: vms,
      child: MaterialApp(
        theme: basaThemeData(Brightness.light),
        home: HomeScreen(title: 'BASA', sections: _sections, onSignedOut: () {}),
      ),
    ));
    await _settle(tester);
  }

  testWidgets('superadmin sees the superadmin-only card', (tester) async {
    late AppViewModels vms;
    await tester.runAsync(() async => vms = await signedIn(null));
    await show(tester, vms);
    expect(find.text('Plain card'), findsOneWidget);
    expect(find.text('Super card'), findsNWidgets(2));
    expect(find.text('SUPER ONLY GROUP'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a school-bound admin does not', (tester) async {
    late AppViewModels vms;
    await tester.runAsync(() async => vms = await signedIn(1));
    await show(tester, vms);
    expect(find.text('Plain card'), findsOneWidget);
    expect(find.text('Super card'), findsNothing);
    expect(find.text('SUPER ONLY GROUP'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  test('the transfers card (row 64) is the superadmin-only one in the admin build', () {
    final entries = adminHomeSections().expand((s) => s.groups).expand((g) => g.entries);
    expect(entries.where((e) => e.superadminOnly).map((e) => e.checklistRow).toList(), [64]);
  });
}
