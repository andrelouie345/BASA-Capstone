// lib/core/services/school_year_dates.dart
//
// Which dates belong to a school year. One rule for every record that
// carries a date of its own (ARAL sessions, imported Phil-IRI readings and
// GSTs): June 1 of the year's first year to July 31 of its second, generous
// on both ends (an early BOSY, a late EOSY, summer remediation).

/// True when [date] (YYYY-MM-DD) falls in [schoolYear] (e.g. 2026-2027).
bool dateInSchoolYear(String date, String schoolYear) {
  final start = int.parse(schoolYear.substring(0, 4));
  return date.compareTo('$start-06-01') >= 0 && date.compareTo('${start + 1}-07-31') <= 0;
}

/// [d] as YYYY-MM-DD.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
