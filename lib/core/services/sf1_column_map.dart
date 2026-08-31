// lib/core/services/sf1_column_map.dart
/// Column indices (0-based) for the SF1 "School Register" sheet, as observed
/// in the sample file. VERIFY against your own converted .xlsx using the
/// `import-preview` console command before running a real import — merged
/// cells and DepEd template revisions can shift these.
class Sf1ColumnMap {
  static const lrn = 0;
  static const lastName = 2;
  static const firstName = 3;
  static const middleName = 4;
  static const sex = 6;
  static const birthDate = 7;
  static const motherTongue = 11;
  static const ipGroup = 13;
  static const religion = 14;
  static const addressStreet = 16;
  static const barangay = 17;
  static const municipality = 19;
  static const province = 21;
  static const fatherName = 27;
  static const motherMaidenName = 31;
  static const guardianName = 35;
  static const guardianRelationship = 43;
  static const contactNumber = 44;
  static const learningModality = 44; // NOTE: verify — sample had ambiguous spacing near here
  static const remarks = 45;

  // Metadata cells (fixed positions in the header block, 0-indexed row/col)
  static const schoolIdRow = 2, schoolIdCol = 5;
  static const schoolNameRow = 3, schoolNameCol = 5;
  static const schoolYearRow = 3, schoolYearCol = 19;
  static const gradeLevelRow = 3, gradeLevelCol = 30;
  static const sectionNameRow = 3, sectionNameCol = 38;

  static const dataStartRow = 6; // first student row, 0-indexed
}