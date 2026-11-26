// The demo SF1 workbooks (demo-data plan Task 7): one per section, at
// <dir>/sf1/<year>/<school>-G<grade>.xlsx, written in the cells the device's
// SF1 import reads (the command pass's writer).
import 'dart:io';

import 'package:basa_capstone/core/services/sf1_column_map.dart';

import '../command_pass/sf1_fixture.dart';
import 'world.dart';

/// An ISO date (2016-09-04) as DepEd's SF1 writes it (09-04-2016); blank stays blank.
String sf1BirthDate(String iso) =>
    iso.isEmpty ? '' : '${iso.substring(5, 7)}-${iso.substring(8, 10)}-${iso.substring(0, 4)}';


/// Writes [section]'s SF1 with [learners] and returns its path; [tag] = a
/// later re-import of the same section (its own subfolder, e.g. `2026-08`).
String writeDemoSf1(Directory dir, DemoSection section, List<DemoLearner> learners, Sf1ColumnMap map,
    {String? tag}) {
  final sep = Platform.pathSeparator;
  final folder = Directory('${dir.path}${sep}sf1$sep${section.year.label}${tag == null ? '' : '$sep$tag'}')
    ..createSync(recursive: true);
  final school = demoSchools.firstWhere((s) => s.code == section.schoolCode);
  final path = '${folder.path}$sep${school.code}-${demoSectionKey(section)}.xlsx';
  writeSf1(
    path,
    map: map,
    schoolCode: school.code,
    schoolName: school.name,
    regionLabel: sf1RegionLabel,
    schoolYear: section.year.label,
    grade: '${section.grade}',
    section: section.name,
    learners: [
      for (final l in learners)
        Sf1Learner(l.lrn, l.last, l.first, l.sex, middle: l.middleInitial, birthDate: sf1BirthDate(l.birthDate)),
    ],
  );
  return path;
}
