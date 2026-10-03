// lib/core/services/sf1_column_map.dart
import 'dart:convert';
import 'dart:io';

/// Column indices (0-based) for the SF1 "School Register" sheet.
/// Runtime-editable and persisted to disk — DepEd template revisions,
/// or a school's locally-modified SF1 export, can shift these without
/// requiring a rebuild. Defaults below match the sample file as of
/// Sep 2026; verify against any new source file via `import-preview`
/// before trusting them.
class Sf1ColumnMap {
  int lrn = 0;
  int lastName = 2;
  int firstName = 3;
  int middleName = 4;
  int sex = 6;
  int birthDate = 7;
  int motherTongue = 11;
  int ipGroup = 13;
  int religion = 14;
  int addressStreet = 15;
  int barangay = 17;
  int municipality = 20;
  int province = 22;
  int fatherName = 27;
  int motherMaidenName = 31;
  int guardianName = 36;
  int guardianRelationship = 40;
  int contactNumber = 41;
  int learningModality = 43;
  int remarks = 44;

  int schoolIdRow = 2, schoolIdCol = 5;
  int regionRow = 2, regionCol = 10;
  int schoolNameRow = 3, schoolNameCol = 5;
  int schoolYearRow = 3, schoolYearCol = 19;
  int gradeLevelRow = 3, gradeLevelCol = 30;
  int sectionNameRow = 3, sectionNameCol = 38;

  int dataStartRow = 6;

  final String _configPath;
  Sf1ColumnMap._(this._configPath);

  static Future<Sf1ColumnMap> load(String directory) async {
    final path = '$directory/sf1_column_map.json';
    final file = File(path);
    final map = Sf1ColumnMap._(path);

    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      map._applyMap(data);
    } else {
      await map._save(); // write out defaults so the file exists from the first run
    }
    return map;
  }

  Future<void> _save() async {
    await File(_configPath).writeAsString(jsonEncode(toMap()));
  }

  Map<String, Object?> toMap() => {
        'lrn': lrn, 'lastName': lastName, 'firstName': firstName, 'middleName': middleName,
        'sex': sex, 'birthDate': birthDate, 'motherTongue': motherTongue, 'ipGroup': ipGroup,
        'religion': religion, 'addressStreet': addressStreet, 'barangay': barangay,
        'municipality': municipality, 'province': province, 'fatherName': fatherName,
        'motherMaidenName': motherMaidenName, 'guardianName': guardianName,
        'guardianRelationship': guardianRelationship, 'contactNumber': contactNumber,
        'learningModality': learningModality, 'remarks': remarks,
        'schoolIdRow': schoolIdRow, 'schoolIdCol': schoolIdCol,
        'regionRow': regionRow, 'regionCol': regionCol,
        'schoolNameRow': schoolNameRow, 'schoolNameCol': schoolNameCol,
        'schoolYearRow': schoolYearRow, 'schoolYearCol': schoolYearCol,
        'gradeLevelRow': gradeLevelRow, 'gradeLevelCol': gradeLevelCol,
        'sectionNameRow': sectionNameRow, 'sectionNameCol': sectionNameCol,
        'dataStartRow': dataStartRow,
      };

  void _applyMap(Map<String, Object?> m) {
    for (final key in toMap().keys) {
      if (m[key] is int) _set(key, m[key] as int);
    }
  }

  /// Returns the current value for a field name, or null if the name
  /// isn't recognized.
  int? get(String field) => toMap()[field] as int?;

  /// Sets a field by name, validates the name, persists on success.
  /// Returns an error message, or null on success.
  Future<String?> set(String field, int value) async {
    if (!toMap().containsKey(field)) {
      return 'Unknown field "$field". Valid fields: ${toMap().keys.join(", ")}';
    }
    if (value < 0) return 'Value must be >= 0 (got $value)';
    _set(field, value);
    await _save();
    return null;
  }

  void _set(String field, int value) {
    switch (field) {
      case 'lrn': lrn = value; break;
      case 'lastName': lastName = value; break;
      case 'firstName': firstName = value; break;
      case 'middleName': middleName = value; break;
      case 'sex': sex = value; break;
      case 'birthDate': birthDate = value; break;
      case 'motherTongue': motherTongue = value; break;
      case 'ipGroup': ipGroup = value; break;
      case 'religion': religion = value; break;
      case 'addressStreet': addressStreet = value; break;
      case 'barangay': barangay = value; break;
      case 'municipality': municipality = value; break;
      case 'province': province = value; break;
      case 'fatherName': fatherName = value; break;
      case 'motherMaidenName': motherMaidenName = value; break;
      case 'guardianName': guardianName = value; break;
      case 'guardianRelationship': guardianRelationship = value; break;
      case 'contactNumber': contactNumber = value; break;
      case 'learningModality': learningModality = value; break;
      case 'remarks': remarks = value; break;
      case 'schoolIdRow': schoolIdRow = value; break;
      case 'schoolIdCol': schoolIdCol = value; break;
      case 'regionRow': regionRow = value; break;
      case 'regionCol': regionCol = value; break;
      case 'schoolNameRow': schoolNameRow = value; break;
      case 'schoolNameCol': schoolNameCol = value; break;
      case 'schoolYearRow': schoolYearRow = value; break;
      case 'schoolYearCol': schoolYearCol = value; break;
      case 'gradeLevelRow': gradeLevelRow = value; break;
      case 'gradeLevelCol': gradeLevelCol = value; break;
      case 'sectionNameRow': sectionNameRow = value; break;
      case 'sectionNameCol': sectionNameCol = value; break;
      case 'dataStartRow': dataStartRow = value; break;
    }
  }
}