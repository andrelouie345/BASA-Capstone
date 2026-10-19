// lib/core/services/srp_rules.dart
//
// Summer Remediation Program (SRP) ranking, as the reading coordinator's
// workbook does it (sheets 01-40, columns GZ/HA): learners not grade level
// ready by the end of the year, weakest first by comprehension, then word
// recognition, then speed. Unlike ARAL (word recognition first), SRP follows
// her sheet (owner 2026-10-19). Equal results share a rank (1, 2, 2, 4 ...);
// a learner is recommended when the rank is within the cap, so a tie at the
// cut brings everyone tied in.

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
