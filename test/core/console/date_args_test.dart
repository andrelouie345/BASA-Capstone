// Strict asof= dates (command pass finding F17).
import 'package:basa_capstone/core/console/date_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real YYYY-MM-DD date is read', () {
    expect(strictDateArg('2026-10-24'), DateTime(2026, 10, 24));
    expect(strictDateArg(' 2028-02-29 '), DateTime(2028, 2, 29));
  });

  test('dates that roll over, other shapes and times are refused', () {
    for (final raw in ['2026-02-30', '2026-13-01', '2027-02-29', '20261024', '2026-10-24T08:00', '2026-1-5', '', 'x']) {
      expect(strictDateArg(raw), isNull, reason: raw);
    }
  });

  test('the refusal names the value', () {
    expect(asofDateMessage('2026-02-30'), 'asof must be a real YYYY-MM-DD date (got "2026-02-30")');
  });
}
