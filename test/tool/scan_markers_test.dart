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

  // The scan builds have the console compiled in: the [debug] markers must be
  // found there, or a misspelled marker would make "no console in release"
  // pass whatever the shipped builds contain.
  test('a required marker missing from any binary fails', () {
    final r = scanMarkers(
      adminMarkers: const [],
      debugMarkers: const [],
      presentMarkers: debug,
      tutorBinaries: {'tutor.so': bin('BASA Debug Console')},
      adminBinaries: {'admin.so': bin('no console here')},
    );
    expect(r.ok, isFalse);
    expect(r.missingRequired, ['admin.so: BASA Debug Console']);
  });

  test('required markers found in every binary pass', () {
    final r = scanMarkers(
      adminMarkers: const [],
      debugMarkers: const [],
      presentMarkers: debug,
      tutorBinaries: {'tutor.so': bin('x BASA Debug Console')},
      adminBinaries: {'admin.so': bin('BASA Debug Console y')},
    );
    expect(r.ok, isTrue);
    expect(r.missingRequired, isEmpty);
  });

  // Dart stores a string with any character outside Latin-1 (an em dash in a
  // command description, say) as UTF-16: the scan must find markers there too.
  List<int> utf16(String text) => [for (final c in text.codeUnits) ...[c & 0xff, c >> 8]];

  test('an admin marker stored as UTF-16 in a tutor binary is a leak', () {
    final r = scan(
      tutor: [0, ...utf16('x — create-user — y'), 0],
      adminBin: bin('Forbidden: only an admin reviews uploads. create-user'),
    );
    expect(r.leaks, ['tutor.so: create-user']);
  });

  test('a required marker stored as UTF-16 counts as present', () {
    final r = scanMarkers(
      adminMarkers: const [],
      debugMarkers: const [],
      presentMarkers: debug,
      tutorBinaries: {'tutor.so': [0, ...utf16('— BASA Debug Console'), 0]},
      adminBinaries: {'admin.so': bin('BASA Debug Console')},
    );
    expect(r.missingRequired, isEmpty);
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
