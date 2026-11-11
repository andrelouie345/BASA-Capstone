// Phil-IRI import, Task 9: matching names and passages (spec
// 2026-11-09-phil-iri-import-design D5, D7) and the owner's scale rule.
import 'package:basa_capstone/core/models/phil_iri_import.dart';
import 'package:basa_capstone/core/models/phil_iri_passage.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/services/phil_iri_import_matching.dart';
import 'package:flutter_test/flutter_test.dart';

Student _s(int id, String last, String first, {String? middle, String sex = 'M'}) =>
    Student(id: id, lrn: '1000000000$id', lastName: last, firstName: first, middleName: middle, sex: sex);

PhilIriPassage _p(int id, int level, String title, {String? set, String? test, bool active = true}) => PhilIriPassage(
      id: id, collectionId: 1, language: 'English', testType: test, setCode: set, level: level,
      title: title, body: 'x', wordCount: 100, isActive: active,
    );

void main() {
  test('name order and punctuation ignored', () {
    expect(philIriNameKey('Dela Cruz, Juan M.'), philIriNameKey('Juan M. Dela Cruz'));
    expect(philIriNameKey('  DELA   CRUZ,juan m'), philIriNameKey('Dela Cruz, Juan M.'));
    final learners = [_s(1, 'Dela Cruz', 'Juan', middle: 'Mendoza'), _s(2, 'Santos', 'Ana', sex: 'F')];
    // The workbook writes the middle initial; SF1 holds the whole middle name.
    expect(philIriNameCandidates(const PhilIriLearnerKey(name: 'DELA CRUZ, Juan M.'), learners).map((s) => s.id), [1]);
    expect(philIriNameCandidates(const PhilIriLearnerKey(name: 'Dela Cruz, Juan'), learners).map((s) => s.id), [1]);
    expect(philIriNameCandidates(const PhilIriLearnerKey(name: 'Dela Cruz, Juan Mendoza'), learners).map((s) => s.id), [1]);
    expect(philIriNameCandidates(const PhilIriLearnerKey(name: 'Dela Cruz, Juan P.'), learners), isEmpty);
  });

  test('same name twice gives two candidates (Review Focus 2)', () {
    final learners = [_s(1, 'Reyes', 'Mark', middle: 'Lim'), _s(2, 'Reyes', 'Mark', middle: 'Lopez'), _s(3, 'Reyes', 'Ana')];
    expect(philIriNameCandidates(const PhilIriLearnerKey(name: 'Reyes, Mark L.'), learners).map((s) => s.id), [1, 2]);
  });

  test('passage titles match across case and punctuation (Review Focus 5)', () {
    final all = [
      _p(10, 4, 'Get Up, Jacky!', set: 'A', test: 'pre'),
      _p(11, 4, "Anansi's Web", set: 'C', test: 'pre'),
      _p(12, 10, 'Butuan Archeological Sites', test: 'pre'),
      _p(13, 7, 'Dust', set: 'C1'),
      _p(14, 7, 'Diving', set: 'A2'),
    ];
    PhilIriPassage? m(String raw, {int? level, String? title}) =>
        philIriMatchPassage(PhilIriImportPassageRef(raw: raw, level: level, title: title), all);
    expect(m('4A Get up, Jacky!')?.id, 10);
    expect(m('Get up, Jacky!', title: 'Get up, Jacky!')?.id, 10);
    expect(m("4C-Pre Anansi's Web")?.id, 11);
    expect(m('10A -Pre Butuan Archeological Sites', level: 10, title: '-Pre Butuan Archeological Sites')?.id, 12);
    expect(m('G10Pre Butuan Archeological Sites')?.id, 12);
    expect(m('7C Dust', level: 7, title: 'Dust')?.id, 13);
    expect(m('G7A2 Diving')?.id, 14);
    expect(m('8C Dust'), isNull, reason: 'level must match');
    expect(m('7C Smoke'), isNull);
  });

  test('inactive passage only when no active one matches; code breaks a tie', () {
    final all = [_p(20, 7, 'Dust', set: 'C1', active: false), _p(21, 7, 'Dust', set: 'C1')];
    expect(philIriMatchPassage(const PhilIriImportPassageRef(raw: '7C Dust'), all)?.id, 21);
    expect(philIriMatchPassage(const PhilIriImportPassageRef(raw: '7C Dust'), [all.first])?.id, 20);
    final twins = [_p(30, 7, 'Lili', test: 'pre'), _p(31, 7, 'Lili', test: 'post')];
    expect(philIriMatchPassage(const PhilIriImportPassageRef(raw: 'G7Post Lili'), twins)?.id, 31);
    expect(philIriMatchPassage(const PhilIriImportPassageRef(raw: 'G7Pre Lili'), twins)?.id, 30);
    // A collection switched off counts as inactive through isActive.
    expect(philIriMatchPassage(const PhilIriImportPassageRef(raw: '7C Dust'), all, isActive: (p) => p.id == 20)?.id, 20);
  });

  test('scale: proportional, nearest whole number (owner 2026-11-11)', () {
    expect(philIriScaleCount(10, 20, 40), 20);
    expect(philIriScaleCount(6, 20, 8), 2); // 2.4
    expect(philIriScaleCount(5, 20, 10), 3); // 2.5 -> 3
    expect(philIriScaleCount(7, 8, 8), 7);
  });
}
