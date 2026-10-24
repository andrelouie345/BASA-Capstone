// The first-admin bootstrap picks the server itself (screen inventory
// ADMIN-G2): the console command no longer builds clients or services.
import 'dart:io';

import 'package:basa_capstone/core/data/remote/supabase_config.dart';
import 'package:basa_capstone/core/services/admin_bootstrap_service.dart';
import 'package:basa_capstone/viewmodels/admin_bootstrap_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _refused(String message) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late AdminBootstrapViewModel vm;

  setUp(() async {
    final config = await SupabaseConfigStore.load(Directory.systemTemp.createTempSync('basa_bootstrap_').path);
    await config.setLan(url: '');
    vm = AdminBootstrapViewModel(config: config, serviceFor: AdminBootstrapService.new);
  });

  test('refuses an unknown target', () async {
    await expectLater(vm.bootstrap('moon', 'a@test', 'A Admin'),
        _refused('Usage: bootstrap-admin <cloud|lan> <email> <full name...>'));
  });

  test('refuses an empty url', () async {
    await expectLater(vm.bootstrap('lan', 'a@test', 'A Admin'), _refused('lan.url not set. Use config-set-lan-url first.'));
  });
}
