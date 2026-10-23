// tool/scan_markers.dart
// Proves what the release binaries contain. tool/admin_markers.txt has named
// sections; the caller picks which one is the admin list and which (if any)
// the debug list:
//   admin list  strings only admin code has: must be in EVERY admin binary
//               (self-test: the marker is real and survives compilation) and
//               in NO tutor binary.
//   debug list  strings only the debug console has: must be in no binary.
//   present     strings that must be in EVERY binary given (the debug list
//               on the scan builds, which have the console: proves those
//               markers are spelled right and survive compilation).
// Usage (run by tool/build_release.ps1):
//   dart run tool/scan_markers.dart --markers tool/admin_markers.txt //       --admin-section admin [--debug-section debug] [--present-section debug] //       --tutor <bin>... --admin <bin>...
// An .apk is read through its lib/arm64-v8a/libapp.so; any other file as is.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

class ScanResult {
  /// `<binary>: <marker>` for each marker found where it must not be.
  final List<String> leaks;

  /// `<binary>: <marker>` for each [admin] marker an admin binary lacks.
  final List<String> missingInAdmin;

  /// `<binary>: <marker>` for each required marker a binary lacks.
  final List<String> missingRequired;

  const ScanResult(this.leaks, this.missingInAdmin, [this.missingRequired = const []]);

  bool get ok => leaks.isEmpty && missingInAdmin.isEmpty && missingRequired.isEmpty;
}

/// Section name (without brackets) -> its lines. Blank lines and `#` comments
/// are skipped; a marker before the first section is an error.
Map<String, List<String>> parseMarkers(String text) {
  final sections = <String, List<String>>{};
  List<String>? into;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final header = RegExp(r'^\[([\w-]+)\]$').firstMatch(line);
    if (header != null) {
      into = sections.putIfAbsent(header.group(1)!, () => []);
    } else if (into == null) {
      throw FormatException('Marker outside a section: $line');
    } else {
      into.add(line);
    }
  }
  return sections;
}

/// Binaries are given by label (file name) so the result names them.
ScanResult scanMarkers({
  required List<String> adminMarkers,
  required List<String> debugMarkers,
  required Map<String, List<int>> tutorBinaries,
  required Map<String, List<int>> adminBinaries,
  List<String> presentMarkers = const [],
}) {
  // latin1 maps every byte to one char, so a byte search becomes String.contains.
  // Dart keeps a string as one byte per char when every char fits Latin-1, and
  // as UTF-16 (little-endian) otherwise (an em dash anywhere in it is enough),
  // so a marker is looked for in both forms.
  String haystack(List<int> bytes) => latin1.decode(bytes);
  bool has(String h, String marker) {
    final oneByte = latin1.decode(utf8.encode(marker));
    final twoByte = String.fromCharCodes([for (final c in marker.codeUnits) ...[c & 0xff, c >> 8]]);
    return h.contains(oneByte) || h.contains(twoByte);
  }

  final leaks = <String>[], missing = <String>[];
  for (final MapEntry(key: label, value: bytes) in tutorBinaries.entries) {
    final h = haystack(bytes);
    for (final m in [...adminMarkers, ...debugMarkers]) {
      if (has(h, m)) leaks.add('$label: $m');
    }
  }
  for (final MapEntry(key: label, value: bytes) in adminBinaries.entries) {
    final h = haystack(bytes);
    for (final m in debugMarkers) {
      if (has(h, m)) leaks.add('$label: $m');
    }
    for (final m in adminMarkers) {
      if (!has(h, m)) missing.add('$label: $m');
    }
  }
  final required = <String>[];
  for (final MapEntry(key: label, value: bytes) in {...tutorBinaries, ...adminBinaries}.entries) {
    final h = haystack(bytes);
    for (final m in presentMarkers) {
      if (!has(h, m)) required.add('$label: $m');
    }
  }
  return ScanResult(leaks, missing, required);
}

List<int> _compiledCode(String path) {
  final bytes = File(path).readAsBytesSync();
  if (!path.endsWith('.apk')) return bytes;
  const so = 'lib/arm64-v8a/libapp.so';
  final file = ZipDecoder().decodeBytes(bytes).findFile(so);
  if (file == null) throw StateError('$path has no $so');
  return file.content;
}

void main(List<String> args) {
  final opts = <String, String>{};
  final tutor = <String>[], admin = <String>[];
  List<String>? into;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (const ['--markers', '--admin-section', '--debug-section', '--present-section'].contains(a) && i + 1 < args.length) {
      opts[a] = args[++i];
      into = null;
    } else if (a == '--tutor') {
      into = tutor;
    } else if (a == '--admin') {
      into = admin;
    } else if (into != null) {
      into.add(a);
    } else {
      stderr.writeln('Unexpected argument: $a');
      exit(64);
    }
  }
  final markersPath = opts['--markers'], adminSection = opts['--admin-section'];
  if (markersPath == null || adminSection == null || tutor.isEmpty || admin.isEmpty) {
    stderr.writeln('Usage: dart run tool/scan_markers.dart --markers <file> --admin-section <name> '
        '[--debug-section <name>] [--present-section <name>] --tutor <bin>... --admin <bin>...');
    exit(64);
  }

  final sections = parseMarkers(File(markersPath).readAsStringSync());
  final adminMarkers = sections[adminSection];
  final debugSection = opts['--debug-section'];
  final debugMarkers = debugSection == null ? const <String>[] : sections[debugSection];
  final presentSection = opts['--present-section'];
  final presentMarkers = presentSection == null ? const <String>[] : sections[presentSection];
  for (final (name, list) in [(adminSection, adminMarkers), (debugSection, debugMarkers), (presentSection, presentMarkers)]) {
    if (list == null) {
      stderr.writeln('No section [$name] in $markersPath');
      exit(64);
    }
  }
  final admins = adminMarkers!, debugs = debugMarkers!, presents = presentMarkers!;
  final result = scanMarkers(
    adminMarkers: admins,
    debugMarkers: debugs,
    presentMarkers: presents,
    tutorBinaries: {for (final f in tutor) f: _compiledCode(f)},
    adminBinaries: {for (final f in admin) f: _compiledCode(f)},
  );
  for (final l in result.leaks) {
    stderr.writeln('LEAK     $l');
  }
  for (final m in result.missingInAdmin) {
    stderr.writeln('MISSING  $m (marker not in the admin build: misspelled, or compiled away?)');
  }
  for (final m in result.missingRequired) {
    stderr.writeln('MISSING  $m (required marker not in this build: misspelled, or compiled away?)');
  }
  if (!result.ok) exit(1);
  stdout.writeln('OK: ${admins.length} [$adminSection] markers in every admin build and in no tutor build'
      '${debugSection == null ? '' : '; ${debugs.length} [$debugSection] markers in no build'}'
      '${presentSection == null ? '' : '; ${presents.length} [$presentSection] markers in every build'}.');
}
