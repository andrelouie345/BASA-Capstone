import 'package:basa_capstone/core/services/school_year_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a school year runs from June 1 of its first year to July 31 of its second', () {
    expect(dateInSchoolYear('2026-06-01', '2026-2027'), isTrue);
    expect(dateInSchoolYear('2027-07-31', '2026-2027'), isTrue);
    expect(dateInSchoolYear('2026-11-12', '2026-2027'), isTrue);
    expect(dateInSchoolYear('2026-05-31', '2026-2027'), isFalse);
    expect(dateInSchoolYear('2027-08-01', '2026-2027'), isFalse);
    expect(dateInSchoolYear('2027-06-03', '2025-2026'), isFalse);
  });

  test('isoDay pads month and day', () {
    expect(isoDay(DateTime(2027, 6, 3)), '2027-06-03');
  });
}
