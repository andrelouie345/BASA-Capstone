// lib/core/services/srp_rules.dart
//
// Summer Remediation Program (SRP) ranking, as the reading coordinator's
// workbook does it (sheets 01-40, columns GZ/HA): learners not grade level
// ready by the end of the year, weakest first by comprehension, then word
// recognition, then speed. Unlike ARAL (word recognition first), SRP follows
// her sheet (owner 2026-10-19). Equal results share a rank (1, 2, 2, 4 ...);
// a learner is recommended when the rank is within the cap, so a tie at the
// cut brings everyone tied in. Classes (sheet "SRP Masterlist"): the
// recommended learners grouped by the grade they were assessed at, split into
// classes of at most 15.

/// What SRP compares, weakest first. Each value is 0 when unknown.
class SrpRankKey implements Comparable<SrpRankKey> {
  final double comprehension;   // 0-1
  final double wordRecognition; // 0-1
  final double speed;           // words per minute

  const SrpRankKey(this.comprehension, this.wordRecognition, this.speed);

  @override
  int compareTo(SrpRankKey o) {
    final a = comprehension.compareTo(o.comprehension);
    if (a != 0) return a;
    final b = wordRecognition.compareTo(o.wordRecognition);
    if (b != 0) return b;
    return speed.compareTo(o.speed);
  }

  @override
  bool operator ==(Object other) => other is SrpRankKey && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(comprehension, wordRecognition, speed);
}

/// The default number of recommended learners per section (her sheet's
/// "15 Recommended Learners").
const srpDefaultPerSection = 15;

/// The default maximum number of learners per SRP class (her "Maximum No. of
/// students per class").
const srpDefaultClassSize = 15;

/// Her SRP Masterlist split: [n] learners into as few classes of at most
/// [maxSize] as possible, as even as possible, the larger classes first
/// (e.g. 32 at 15 -> 11, 11, 10).
List<int> srpClassSizes(int n, int maxSize) {
  if (n <= 0) return const [];
  final classes = (n + maxSize - 1) ~/ maxSize;
  final base = n ~/ classes, extra = n % classes;
  return [for (var i = 0; i < classes; i++) base + (i < extra ? 1 : 0)];
}

/// Her class names: learners in Grade [grade] assessed at Grade [assessed]
/// get 7-3A, 7-3B ...; Non-Readers ([assessed] 0) 7A-SHARP, 7B-SHARP ...
String srpClassName(int grade, int assessed, int index) {
  final letter = _letters(index);
  return assessed == 0 ? '$grade$letter-SHARP' : '$grade-$assessed$letter';
}

/// A, B, ... Z, AA, AB ... (spreadsheet column letters) for index 0, 1, ...
String _letters(int index) {
  var n = index + 1;
  final chars = <String>[];
  while (n > 0) {
    chars.insert(0, String.fromCharCode(65 + (n - 1) % 26));
    n = (n - 1) ~/ 26;
  }
  return chars.join();
}

/// Rank per index into [keys], 1 = weakest; equal keys share a rank.
List<int> srpRanks(List<SrpRankKey> keys) {
  final order = List<int>.generate(keys.length, (i) => i)..sort((a, b) => keys[a].compareTo(keys[b]));
  final ranks = List<int>.filled(keys.length, 0);
  for (var pos = 0; pos < order.length; pos++) {
    final i = order[pos];
    ranks[i] = pos > 0 && keys[order[pos - 1]] == keys[i] ? ranks[order[pos - 1]] : pos + 1;
  }
  return ranks;
}
