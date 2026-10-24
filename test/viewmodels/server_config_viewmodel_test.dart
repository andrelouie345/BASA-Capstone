// Server settings through a ViewModel (screen inventory AUTH-G2): the screen
// never touches the config store, and keys are masked the console's way.
import 'dart:io';

import 'package:basa_capstone/core/data/remote/supabase_config.dart';
import 'package:basa_capstone/viewmodels/server_config_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String dir;
  late ServerConfigViewModel vm;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('basa_server_config_').path;
    vm = ServerConfigViewModel(config: await SupabaseConfigStore.load(dir));
  });

  test('masks a long key', () async {
    await vm.setCloud(anonKey: 'abcdefghijklmnop');

    expect(vm.show().cloudKeyMasked, 'abcd...mnop');
  });

  test('masks a short key with stars', () async {
    await vm.setLan(anonKey: 'short');

    expect(vm.show().lanKeyMasked, '*****');
  });

  test('empty key is (not set)', () async {
    await vm.setCloud(anonKey: '');

    expect(vm.show().cloudKeyMasked, '(not set)');
  });

  test('setCloud persists the url', () async {
    await vm.setCloud(url: 'https://example.test');

    final reloaded = ServerConfigViewModel(config: await SupabaseConfigStore.load(dir));
    expect(reloaded.show().cloudUrl, 'https://example.test');
  });
}
