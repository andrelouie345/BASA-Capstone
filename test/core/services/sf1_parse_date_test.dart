// SF1 birth dates (owner 2026-11-15): MM-DD-YYYY (DepEd's), MM/DD/YYYY and
// YYYY-MM-DD (also with a time, as an Excel date cell reads) are read; the
// date must be real; anything else is "unreadable" (the import leaves it
// blank with a row warning). A blank cell is just blank.
import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readable forms', () {
    expect(sf1ParseDate('03-15-2013'), (iso: '2013-03-15', unreadable: false));
    expect(sf1ParseDate('3-5-2013'), (iso: '2013-03-05', unreadable: false));
    expect(sf1ParseDate('03/15/2013'), (iso: '2013-03-15', unreadable: false));
    expect(sf1ParseDate('2013-03-15'), (iso: '2013-03-15', unreadable: false));
    expect(sf1ParseDate('2013-03-15 00:00:00.000'), (iso: '2013-03-15', unreadable: false));
    expect(sf1ParseDate('2013-03-15T00:00:00'), (iso: '2013-03-15', unreadable: false));
    expect(sf1ParseDate(' 02-29-2012 '), (iso: '2012-02-29', unreadable: false)); // leap year
  });

  test('blank is not a problem', () {
    expect(sf1ParseDate(null), (iso: null, unreadable: false));
    expect(sf1ParseDate('   '), (iso: null, unreadable: false));
  });

  test('unreadable: not a date, not a real date, odd years', () {
    for (final raw in ['15/13/2013', '02-30-2013', '02-29-2013', 'March 15, 2013', '15-2013-03', '13-03-15',
        '03-15-1850', '03-15-2150', '00-10-2013']) {
      expect(sf1ParseDate(raw), (iso: null, unreadable: true), reason: raw);
    }
  });
}
