// The demo coverage report (demo-data plan Task 12, spec section 6): one
// line per spec row, OK only when every check reaches its minimum, and the
// report never prints a password.
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/coverage.dart';

void main() {
  /// Every check at its minimum.
  Map<String, int> enough() => {for (final c in coverageChecks) c.key: c.min};

  test('one line per spec section 6 row (19), in the spec order', () {
    final lines = coverageLines(enough());
    expect(lines, hasLength(19));
    expect(lines.first.area, 'Accounts');
    expect(lines.last.area, 'Settings');
    expect(lines.every((l) => l.ok), isTrue);
    expect(lines.every((l) => l.checks.isNotEmpty), isTrue);
  });

  test('the CRLA row checks the attempts marked in BASA (digitized, at least 10)', () {
    final crla = coverageRows.singleWhere((r) => r.area == 'CRLA');
    final digitized = crla.checks.singleWhere((c) => c.key == 'crla.digitized');
    expect(digitized.min, 10);
  });

  test('a count below its minimum, or missing, makes that line GAP', () {
    final counts = enough();
    final idle = coverageChecks.singleWhere((c) => c.key == 'aral.idleClasses');
    counts[idle.key] = idle.min - 1;
    counts.remove('sync.rejected');
    final lines = coverageLines(counts);
    final gaps = lines.where((l) => !l.ok).map((l) => l.area).toList();
    expect(gaps, ['ARAL', 'Sync']);
    final report = coverageReport(lines, server: 'https://x.supabase.co', today: DateTime(2026, 11, 27));
    expect(report, contains('GAP'));
    expect(RegExp(r'\| GAP \|').allMatches(report), hasLength(2));
    expect(report, contains('2 gap(s)'));
  });

  test('all OK says so', () {
    final report = coverageReport(coverageLines(enough()), server: 's', today: DateTime(2026, 11, 27));
    expect(report, contains('19 of 19 lines OK'));
    expect(report, isNot(contains('| GAP |')));
  });

  test('the report never contains a password', () {
    const secret = 'Nc9!SuperSecretPassw0rd';
    final report = coverageReport(
      coverageLines(enough()),
      server: 's',
      today: DateTime(2026, 11, 27),
      accounts: {
        'coord.hs': {'email': 'coord.hs@nightcity.test', 'password': secret},
        'tutor1.es': {'email': 'tutor1.es@nightcity.test', 'password': '${secret}2'},
      },
    );
    expect(report, contains('coord.hs@nightcity.test'));
    expect(report, isNot(contains(secret)));
    expect(report, isNot(contains('Nc9!')));
  });

  test('who administered what: a row per school, year, instrument and round', () {
    final report = coverageReport(coverageLines(enough()), server: 's', today: DateTime(2026, 11, 27), administered: [
      const AdministeredRow('NCHS-DEMO', '2026-2027', 'Phil-IRI', 'mosy1', sectionTutors: 60, classTutors: 70, both: 5, coordinators: 0),
    ]);
    expect(report, contains('| NCHS-DEMO | 2026-2027 | Phil-IRI | mosy1 | 60 | 70 | 5 | 0 | 0 |'));
  });
}
