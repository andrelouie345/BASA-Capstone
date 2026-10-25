// Coverage count of the command pass (tool/command_pass/coverage.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/command_pass/coverage.dart';
import '../../../tool/command_pass/scenario.dart';

List<String> _list(String file) =>
    File('test/core/wiring/$file').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

void main() {
  // whoami: both builds. user-list: admin only.
  const tutorCmds = ['whoami'];
  const adminCmds = ['user-list', 'whoami'];
  CoverageResult cov(String source) =>
      computeCoverage([parseScenario('x', source)], tutorCommands: tutorCmds, adminCommands: adminCmds);

  test('a checked run on a tutor device covers a shared command for both builds', () {
    final r = cov('device p tutor\nrun whoami\nexpect Signed in');
    expect(r.uncoveredTutor, isEmpty);
    expect(r.coveredTutor, 1);
    expect(r.uncoveredAdmin, ['user-list']);
    expect(r.coveredAdmin, 1);
  });

  test('a shared command run only on an admin device leaves the tutor build uncovered', () {
    final r = cov('device pc admin\nrun whoami\nexpect Signed in\nrun user-list\nrefuse Forbidden');
    expect(r.uncoveredTutor, ['whoami']);
    expect(r.uncoveredAdmin, isEmpty);
    expect(r.coveredAdmin, 2);
  });

  test('an admin-only command run on a tutor device does not count', () {
    final r = cov('device p tutor\nrun user-list\nexpect Unknown command');
    expect(r.uncoveredAdmin, contains('user-list'));
  });

  test('an unchecked run does not count', () {
    final r = cov('device p tutor\nrun whoami\ncapture me = as (\\S+)\nrun whoami\nas tutor1\nrun whoami');
    expect(r.uncoveredTutor, ['whoami']);
  });

  test('sql and expect~ count as checks', () {
    expect(cov('device p tutor\nrun whoami\nsql select 1 => 1').uncoveredTutor, isEmpty);
    expect(cov('device p tutor\nrun whoami\nexpect~ Signed').uncoveredTutor, isEmpty);
  });

  test('arguments do not change the command name', () {
    expect(cov('device p tutor\nrun whoami extra args\nexpect x').uncoveredTutor, isEmpty);
  });

  test('a run before any device does not count', () {
    expect(cov('run whoami\nexpect x').uncoveredTutor, ['whoami']);
  });

  test('coverage spans scenarios', () {
    final r = computeCoverage([
      parseScenario('a', 'device pc admin\nrun user-list\nexpect x'),
      parseScenario('b', 'device p tutor\nrun whoami\nexpect y'),
    ], tutorCommands: tutorCmds, adminCommands: adminCmds);
    expect(r.uncoveredTutor, isEmpty);
    expect(r.uncoveredAdmin, isEmpty);
  });

  // Each batch can be rerun alone, so a scenario never inherits a device.
  test('the device does not carry over to the next scenario', () {
    final r = computeCoverage([
      parseScenario('a', 'device p tutor\nrun whoami\nexpect x'),
      parseScenario('b', 'run user-list\nexpect y'),
    ], tutorCommands: tutorCmds, adminCommands: adminCmds);
    expect(r.uncoveredAdmin, ['user-list']);
  });

  test('totals come from the real command lists', () {
    final r = computeCoverage(const [], tutorCommands: _list('tutor_commands.txt'), adminCommands: _list('admin_commands.txt'));
    expect(r.totalTutor, 125);
    expect(r.totalAdmin, 246);
    expect(r.uncoveredTutor, hasLength(125));
    expect(r.coveredTutor + r.coveredAdmin, 0);
  });
}
