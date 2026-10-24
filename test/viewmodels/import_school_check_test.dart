// F24 (command pass): a school-bound admin or coordinator importing another
// school's SF1 got the raw RLS error of the school insert. The ViewModel now
// refuses before anything is written.
import 'package:basa_capstone/core/models/school.dart';
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final own = School(id: 36, schoolId: '999001', schoolName: 'ZZTEST Own', regionId: 13);

  test('the own school file passes', () {
    expect(sf1OtherSchoolRefusal(fileSchoolCode: '999001', fileSchoolName: 'ZZTEST Own', ownSchool: own), isNull);
    expect(sf1OtherSchoolRefusal(fileSchoolCode: ' 999001 ', fileSchoolName: 'x', ownSchool: own), isNull);
  });

  test('another school file is refused with its code and name', () {
    expect(
      sf1OtherSchoolRefusal(fileSchoolCode: '999002', fileSchoolName: 'ZZTEST B', ownSchool: own),
      'Forbidden: this roster is for school 999002 (ZZTEST B); '
      "you can only import your own school's rosters.",
    );
  });

  test('a caller whose school cannot be read is refused', () {
    expect(
      sf1OtherSchoolRefusal(fileSchoolCode: '999001', fileSchoolName: 'ZZTEST Own', ownSchool: null),
      'Forbidden: your school could not be read, so the roster cannot be checked.',
    );
  });
}
