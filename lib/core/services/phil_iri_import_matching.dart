// lib/core/services/phil_iri_import_matching.dart
//
// Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md,
// D5 and D7; plan Task 9): matching a file's learner names and passage names
// to BASA's, plus the scale conversion the owner chose (2026-11-11). Pure
// Dart; the ViewModel decides what a match means.
import '../models/phil_iri_import.dart';
import '../models/phil_iri_passage.dart';
import '../models/student.dart';

final _nonLetters = RegExp(r'[^\p{L}]+', unicode: true);

/// A name reduced for matching: lowercase, letters only, words sorted. So
/// "Dela Cruz, Juan M." == "Juan M. Dela Cruz" and "Get up, Jacky!" ==
/// "Get Up, Jacky!".
String philIriNameKey(String name) {
  final words = name.toLowerCase().split(_nonLetters).where((w) => w.isNotEmpty).toList()..sort();
  return words.join(' ');
}

/// The keys a BASA learner answers to: the full name, the name with the
/// middle initial, and the name without a middle name (ma's workbook writes
/// "Last, First M."; SF1 holds the whole middle name).
Set<String> philIriLearnerKeys(Student s) {
  final middle = (s.middleName ?? '').trim();
  final base = '${s.lastName} ${s.firstName}';
  return {
    philIriNameKey('$base $middle'),
    if (middle.isNotEmpty) philIriNameKey('$base ${middle.substring(0, 1)}'),
    philIriNameKey(base),
  };
}

/// The learners of [learners] whose name matches [key]'s name. Sex is not
/// checked here (the ViewModel cross-checks it).
List<Student> philIriNameCandidates(PhilIriLearnerKey key, List<Student> learners) {
  final name = key.name;
  if (name == null) return const [];
  final k = philIriNameKey(name);
  if (k.isEmpty) return const [];
  return [for (final s in learners) if (philIriLearnerKeys(s).contains(k)) s];
}

// "7C Dust", "7D2 Ecosystems", "4C-Pre Anansi's Web", "10A -Pre Butuan ...",
// "G7C1 Dust", "G10Pre Butuan ...".
final _passageName = RegExp(r'^\s*[Gg]?(\d{1,2})([A-Za-z]*\d*)\s*(?:-\s*(?:pre|post)\b)?\s*(.*)$', caseSensitive: false);

/// A set code compared across sources: the workbook's `7C` is BASA's `C1`
/// (a letter alone is its first passage), `7A2` is `A2`; `Pre`/`Post` stay.
String _codeKey(String code) {
  final c = code.toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(c) ? '${c}1' : c;
}

/// The BASA passage [ref] names, among [all]: same level (when the name
/// gives one) and the same title by [philIriNameKey]. Active passages first
/// ([isActive], default the passage's own flag); an inactive one only when
/// no active one matches (history may use a passage switched off since).
/// Several left: the one whose set code matches the file's code, else the
/// first. Null when nothing matches.
PhilIriPassage? philIriMatchPassage(
  PhilIriImportPassageRef ref,
  List<PhilIriPassage> all, {
  bool Function(PhilIriPassage)? isActive,
}) {
  var level = ref.level;
  String? code;
  var title = ref.title;
  final m = _passageName.firstMatch(ref.raw);
  if (m != null && m.group(1) != null) {
    level ??= int.parse(m.group(1)!);
    code = m.group(2);
    final t = m.group(3)!.trim();
    // A reader may have kept "-Pre Title" as the title; the raw name wins.
    if (t.isNotEmpty) title = t;
  }
  title ??= ref.raw;
  final want = philIriNameKey(title);
  if (want.isEmpty) return null;
  final active = isActive ?? (PhilIriPassage p) => p.isActive;

  final matches = [
    for (final p in all)
      if ((level == null || p.level == level) && philIriNameKey(p.title) == want) p,
  ];
  if (matches.isEmpty) return null;
  final activeOnes = matches.where(active).toList();
  final pool = activeOnes.isNotEmpty ? activeOnes : matches;
  if (code != null && code.isNotEmpty && pool.length > 1) {
    final k = _codeKey(code);
    for (final p in pool) {
      final own = p.setCode ?? (p.testType == 'pre' ? 'Pre' : p.testType == 'post' ? 'Post' : null);
      if (own != null && _codeKey(own) == k) return p;
    }
  }
  return pool.first;
}

/// [count] out of [from] on a scale of [to] (owner 2026-11-11: a workbook
/// comprehension or GST out of another maximum is converted proportionally;
/// 10 of 20 -> 20 of 40). Rounded to the nearest whole number, halves up.
int philIriScaleCount(int count, int from, int to) => from == to ? count : (count * to / from).round();
