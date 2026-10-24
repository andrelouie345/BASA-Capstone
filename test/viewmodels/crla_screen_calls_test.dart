// CRLA calls a screen needs without console code (screen inventory
// docs/handoff/screens/crla.md, CRLA-G1 and CRLA-G2).
import 'dart:io';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/crla_types.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/crla_threshold_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

void main() {
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_calls_').path);
    t = wireTutor(ctx, wireShared(ctx));
    await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-00000000cc01', email: 'crla@test', role: 'tutor', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'crla@test', password: 'test-pw'), isNull);
  });

  test('startAssessment refuses mt without a language', () async {
    await expectLater(
        t.crlaVm.startAssessment(
            studentId: 1, sectionId: 1, schoolYear: '2026-2027', subjectVariant: 'mt', round: CrlaRound.bosy),
        throwsA(isA<ViewModelException>()
            .having((e) => e.message, 'message', 'The mt variant needs a language (e.g. Cebuano).')));
  });

  test('threshold layers carry the defaults', () {
    final layers = CrlaThresholdLayers(null, null, CrlaThresholds.defaults);

    expect(layers.defaults.toMap(), CrlaThresholds.defaults.toMap());
  });
}
