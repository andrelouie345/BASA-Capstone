// The binary marker scan behind tool/build_release.ps1, on byte fixtures.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/scan_markers.dart';

List<int> bin(String text) => [0, 1, 2, ...utf8.encode(text), 255, 0];

void main() {
  const admin = ['Forbidden: only an admin reviews uploads.', 'create-user'];
  const debug = ['BASA Debug Console'];

  ScanResult scan({required List<int> tutor, required List<int> adminBin}) => scanMarkers(
        adminMarkers: admin,
        debugMarkers: debug,
        tutorBinaries: {'tutor.so': tutor},
        adminBinaries: {'admin.so': adminBin},
      );

  test('clean tutor and complete admin pass', () {
    final r = scan(
      tutor: bin('sign-in whoami'),
      adminBin: bin('x Forbidden: only an admin reviews uploads. y create-user z'),
    );
    expect(r.ok, isTrue);
    expect(r.leaks, isEmpty);
    expect(r.missingInAdmin, isEmpty);
  });

  test('admin marker in tutor binary is a leak', () {
    final r = scan(
      tutor: bin('... create-user ...'),
      adminBin: bin('Forbidden: only an admin reviews uploads. create-user'),
    );
    expect(r.ok, isFalse);
    expect(r.leaks, ['tutor.so: create-user']);
  });

  test('debug marker in any binary is a leak', () {
    final r = scan(
      tutor: bin('clean'),
      adminBin: bin('Forbidden: only an admin reviews uploads. create-user BASA Debug Console'),
    );
    expect(r.ok, isFalse);
    expect(r.leaks, ['admin.so: BASA Debug Console']);
  });

  test('missing in admin binary fails', () {
    final r = scan(tutor: bin('clean'), adminBin: bin('create-user only'));
    expect(r.ok, isFalse);
    expect(r.missingInAdmin, ['admin.so: Forbidden: only an admin reviews uploads.']);
  });

  test('marker file sections are parsed', () {
    final m = parseMarkers('# comment\n[admin]\ncreate-user\n\n[admin-release]\nUserViewModel\n[debug]\nBASA Debug Console\n');
    expect(m['admin'], ['create-user']);
    expect(m['admin-release'], ['UserViewModel']);
    expect(m['debug'], ['BASA Debug Console']);
  });

  test('a marker before any section is refused', () {
    expect(() => parseMarkers('create-user\n[admin]\n'), throwsFormatException);
  });
}
