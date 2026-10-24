// Auth calls a screen needs without console code (screen inventory
// docs/handoff/screens/auth.md, AUTH-G1 and AUTH-G3).
import 'dart:io';

import 'package:basa_capstone/core/release.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/services/offline_signin_rules.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

void main() {
  late AppContext ctx;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_auth_calls_').path);
  });

  test('offlineStatus returns null without a saved credential', () async {
    await ctx.localDb.delete('offline_credentials');

    expect(await ctx.authVm.offlineStatus(), isNull);
  });

  test('offlineStatus window ends lastOnline + windowDays', () async {
    await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-00000000ab01', email: 'own@test', role: 'tutor');

    final s = (await ctx.authVm.offlineStatus())!;

    expect(s.email, 'own@test');
    expect(s.windowDays, 14);
    expect(s.until, DateTime.parse(s.lastOnlineAt).add(const Duration(days: 14)));
    expect(s.failedAttempts, 0);
    expect(s.maxFailedAttempts, offlineMaxFailedAttempts);
  });

  test('appRelease lists basaMigrations in order', () {
    final r = ctx.authVm.appRelease();

    expect(r, hasLength(basaMigrations.length));
    expect(r.first, '${basaMigrations.keys.first}_${basaMigrations.values.first}');
    expect(r.last, '${basaMigrations.keys.last}_${basaMigrations.values.last}');
  });

  test('versionReport refuses signed out', () async {
    await expectLater(ctx.authVm.versionReport(),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', notSignedInMessage)));
  });
}
