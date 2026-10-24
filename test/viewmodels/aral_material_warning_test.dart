// ARAL material messages a screen shows as they are carry no exception or
// database text; the detail goes to the log (spec
// docs/superpowers/specs/2026-10-24-vm-completeness-design.md, class E:
// ARAL-G7 and the CHECK refusal).
import 'package:basa_capstone/core/console/logger.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_material.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/aral_enrollment_repository.dart';
import 'package:basa_capstone/core/repositories/aral_material_repository.dart';
import 'package:basa_capstone/core/repositories/aral_setting_repository.dart';
import 'package:basa_capstone/core/repositories/section_repository.dart';
import 'package:basa_capstone/viewmodels/aral_material_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import '../helpers/fake_online_auth.dart';

final _material = AralMaterial(id: 7, schoolId: 1, title: 'Story cards', keyStage: AralKeyStage.ks1);

class _Materials implements AralMaterialRepository {
  final bool mirrorFails;
  final bool checkFails;
  _Materials({this.mirrorFails = false, this.checkFails = false});

  @override
  Future<AralMaterial?> findById(int id) async => _material;
  @override
  Future<void> delete(int id) async {
    if (checkFails) {
      throw const PostgrestException(message: 'new row violates check constraint "aral_materials_grades"', code: '23514');
    }
  }

  @override
  Future<void> removeMirrored(int id) async {
    if (mirrorFails) throw Exception('locked db');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoRoster implements AralEnrollmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSections implements SectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSettings implements AralSettingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lines implements Logger {
  final lines = <String>[];
  @override
  void log(String source, String message) => lines.add(message);
}

AralMaterialViewModel _vm(_Materials local, _Materials cloud, Logger logger) => AralMaterialViewModel(
      auth: FakeOnlineAuth(UserRole.coordinator),
      local: local,
      cloud: (_) => cloud,
      roster: _NoRoster(),
      sections: _NoSections(),
      localSettings: _NoSettings(),
      logger: logger,
    );

void main() {
  test('AralMaterialViewModel mirror warning has no exception text', () async {
    final log = _Lines();
    final vm = _vm(_Materials(mirrorFails: true), _Materials(), log);

    await vm.deleteMaterial(7);

    expect(vm.lastMirrorWarning,
        'The catalog was changed online, but the local copy was not updated. Run pull-cloud.');
    expect(log.lines.any((l) => l.contains('locked db')), isTrue);
  });

  test('a CHECK refusal has no database text', () async {
    final log = _Lines();
    final vm = _vm(_Materials(), _Materials(checkFails: true), log);

    await expectLater(
        vm.deleteMaterial(7),
        throwsA(isA<ViewModelException>()
            .having((e) => e.message, 'message', 'The database refused the values.')));
    expect(log.lines.any((l) => l.contains('aral_materials_grades')), isTrue);
  });
}
