// Theme colours: saved per device in <data dir>/theme_settings.json, read back
// after a restart, defaults when the file is missing or broken.
import 'dart:io';

import 'package:basa_capstone/core/data/local/theme_settings_store.dart';
import 'package:basa_capstone/core/models/theme_settings.dart';
import 'package:basa_capstone/viewmodels/theme_settings_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  File file() => File('${dir.path}/theme_settings.json');
  Future<ThemeSettingsViewModel> open() async =>
      ThemeSettingsViewModel(store: await ThemeSettingsStore.load(dir.path));

  setUp(() => dir = Directory.systemTemp.createTempSync('basa_theme_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('no file: defaults, and nothing is written', () async {
    final vm = await open();
    expect(vm.current().mode, ThemeModeChoice.system);
    expect(vm.current().light, isEmpty);
    expect(vm.current().dark, isEmpty);
    expect(file().existsSync(), isFalse);
  });

  test('changes survive a restart', () async {
    final vm = await open();
    await vm.setMode(ThemeModeChoice.dark);
    await vm.setColor(ThemeBrightness.light, 'primary', 0xFF1E88E5);
    await vm.setColor(ThemeBrightness.dark, 'surface', 0x80121212);

    final again = (await open()).current();
    expect(again.mode, ThemeModeChoice.dark);
    expect(again.light, {'primary': 0xFF1E88E5});
    expect(again.dark, {'surface': 0x80121212});
  });

  test('clearColor puts one colour back; reset deletes the file', () async {
    final vm = await open();
    await vm.setColor(ThemeBrightness.light, 'primary', 0xFF000000);
    await vm.setColor(ThemeBrightness.light, 'secondary', 0xFF111111);
    await vm.clearColor(ThemeBrightness.light, 'primary');
    expect(vm.current().light, {'secondary': 0xFF111111});

    await vm.setMode(ThemeModeChoice.light);
    await vm.reset();
    expect(vm.current().mode, ThemeModeChoice.system);
    expect(vm.current().light, isEmpty);
    expect(file().existsSync(), isFalse);
  });

  test('a bad name or value is refused with a readable message', () async {
    final vm = await open();
    expect(() => vm.setColor(ThemeBrightness.light, '9bad', 0xFF000000), throwsA(isA<ViewModelException>()));
    expect(() => vm.setColor(ThemeBrightness.light, 'primary', 0x1FFFFFFFF), throwsA(isA<ViewModelException>()));
    expect(() => vm.setColor(ThemeBrightness.light, 'primary', -1), throwsA(isA<ViewModelException>()));
    expect(file().existsSync(), isFalse);
  });

  test('a broken or hand-edited file gives defaults for what is unreadable', () async {
    file().writeAsStringSync('{not json');
    expect((await open()).current().mode, ThemeModeChoice.system);

    file().writeAsStringSync('{"mode":"sepia","light":{"primary":4280191205,"9bad":1,"x":"red"},"dark":[]}');
    final t = (await open()).current();
    expect(t.mode, ThemeModeChoice.system);
    expect(t.light, {'primary': 4280191205});
    expect(t.dark, isEmpty);
  });
}
