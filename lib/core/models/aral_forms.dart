// lib/core/models/aral_forms.dart
//
// The data of ARAL Forms 1, 2 and 4 (Reading), Division Memorandum 180 s. 2026
// (ARAL memo Plan B; AralFormsViewModel builds them, aral_forms_xlsx.dart
// writes them). Plain values: '' for a blank cell, never null.

/// Form 1/2 Phil-IRI result at grade level (the report's 'GLR').
const aralFormGradeLevel = 'Grade level';
const aralFormFrustration = 'Frustration';
const aralFormInstructional = 'Instructional';
/// Form 2: the class's learners don't share one MoSY result.
const aralFormMixed = 'mixed';

class AralForm1Row {
  final String lrn;
  final String name;          // Last, First M.
  final String sex;           // M / F / ''
  final int? homeGrade;
  final String section;
  final String adviser;
  final String mosyTool;      // CRLA / Phil-IRI / '' (no MoSY result of their own)
  final String mosyResult;
  final String workbookIssued = '';
  final String remarks = '';

  AralForm1Row({
    required this.lrn,
    required this.name,
    required this.sex,
    required this.homeGrade,
    required this.section,
    required this.adviser,
    required this.mosyTool,
    required this.mosyResult,
  });
}

/// Form 1, one class.
class AralForm1 {
  final String schoolName;
  final String schoolCode;    // DepEd school ID
  final String classCode;     // the class name
  final int grade;            // the class's home grade
  final String learningArea = 'Reading';
  final String tutorName;
  final String tutorType;     // Internal / External / ''
  final String sessionType;
  final String schedule;      // days and time
  final String venue;
  final List<AralForm1Row> rows;
  final List<String> blanks;

  AralForm1({
    required this.schoolName,
    required this.schoolCode,
    required this.classCode,
    required this.grade,
    required this.tutorName,
    required this.tutorType,
    required this.sessionType,
    required this.schedule,
    required this.venue,
    required this.rows,
    required this.blanks,
  });

  int get male => rows.where((r) => r.sex == 'M').length;
  int get female => rows.where((r) => r.sex == 'F').length;
  int get total => rows.length;
}

class AralForm2Row {
  final String classCode;
  final int grade;
  final String area = 'R';
  final int male, female, total;
  final String mosyResult;    // the shared result, 'mixed' or ''
  final String tutorName;
  final String tutorType;     // I / E / ''
  final String advisoryClass; // the tutor's advisory section(s)
  final String schedule;
  final String sessionType;
  final String venue;

  AralForm2Row({
    required this.classCode,
    required this.grade,
    required this.male,
    required this.female,
    required this.total,
    required this.mosyResult,
    required this.tutorName,
    required this.tutorType,
    required this.advisoryClass,
    required this.schedule,
    required this.sessionType,
    required this.venue,
  });
}

class AralForm2 {
  final String schoolName;
  final String schoolCode;
  final List<AralForm2Row> rows;
  final int readingClasses, readingLearners, internalTutors, externalTutors;
  final List<String> blanks;
  final List<String> notes;

  AralForm2({
    required this.schoolName,
    required this.schoolCode,
    required this.rows,
    required this.readingClasses,
    required this.readingLearners,
    required this.internalTutors,
    required this.externalTutors,
    required this.blanks,
    required this.notes,
  });
}

/// Form 4 Part I, one grade (Reading columns).
class AralForm4Grade {
  final int grade;
  int identified = 0;
  int served = 0;
  int reachedGradeLevel = 0;
  int improved = 0;
  int noImprovement = 0;
  int atMosy = 0;

  AralForm4Grade(this.grade);
}

class AralForm4 {
  final String schoolName;
  final String schoolCode;
  final String asOf;
  final List<AralForm4Grade> grades; // 1..10
  final int classes, internalTutors, externalTutors, sessions;
  final double hours;                // sum of session minutes / 60
  final List<String> notes;

  AralForm4({
    required this.schoolName,
    required this.schoolCode,
    required this.asOf,
    required this.grades,
    required this.classes,
    required this.internalTutors,
    required this.externalTutors,
    required this.sessions,
    required this.hours,
    required this.notes,
  });
}
