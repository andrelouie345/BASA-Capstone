// lib/core/services/nla_form2b.dart
//
// The categories of the NLA portal's Phil-IRI for JHS Form 2b, as the reading
// coordinator computes them (workbook sheet "Phil-IRI Form 2"; she confirmed
// them 2026-10-19). A learner's round comprehension % (the carried, higher
// score) falls in one band:
//
//   Grade Level Ready ("Scored 70% and better")   >= 68.5%
//   2 Level Down ("Score 16-27"): Independent      53.5 - 68.5
//                                 Instructional    40.5 - 53.5
//                                 Frustration      38.5 - 40.5
//   3 Level Down ("Score 0-15"):  Independent      28.5 - 38.5
//                                 Instructional    25.5 - 28.5
//                                 Frustration      above 0, below 25.5
//
// (The Frustration profile has the 2-LD/3-LD sub-levels; each is split again
// into Independent/Instructional/Frustration; 3-LD Frustration also covers
// learners further below.) Compared on the raw fraction, as in her sheet. A
// comprehension of 0 or none is not counted (not assessed).
//
// The GST blocks (BOSY): the raw GST score in 0-15 / 16-27 / 28-40 (out of 40;
// Grades 4-6, out of 20, by the same percentages: below 40%, below 70%, 70% and
// up) and the GST comprehension profile. Her sheet counts the score block on the
// comprehension fraction (so everyone lands in 0-15) and counts a learner
// without a GST as Frustration; BASA uses the GST score and only learners who
// took it (a GST of 0 is not an assessment, reading coordinator 2026-10-18).
library;

enum NlaBand {
  glr('Grade Level Ready'),
  ld2Independent('2-LD Independent'),
  ld2Instructional('2-LD Instructional'),
  ld2Frustration('2-LD Frustration'),
  ld3Independent('3-LD Independent'),
  ld3Instructional('3-LD Instructional'),
  ld3Frustration('3-LD Frustration');

  final String label;
  const NlaBand(this.label);

  bool get is2Ld => this == ld2Independent || this == ld2Instructional || this == ld2Frustration;
  bool get is3Ld => this == ld3Independent || this == ld3Instructional || this == ld3Frustration;
}

/// The band of a round comprehension (0-1), or null when it isn't counted (0 or none).
NlaBand? nlaBand(double? comprehension) {
  final c = comprehension;
  if (c == null || c <= 0) return null;
  if (c >= 0.685) return NlaBand.glr;
  if (c >= 0.535) return NlaBand.ld2Independent;
  if (c >= 0.405) return NlaBand.ld2Instructional;
  if (c >= 0.385) return NlaBand.ld2Frustration;
  if (c >= 0.285) return NlaBand.ld3Independent;
  if (c >= 0.255) return NlaBand.ld3Instructional;
  return NlaBand.ld3Frustration;
}

enum NlaGstBand {
  score0to15('Score 0-15'),
  score16to27('Score 16-27'),
  score28to40('Score 28-40');

  final String label;
  const NlaGstBand(this.label);
}

/// The GST score band (a score of 0 is not counted).
NlaGstBand? nlaGstBand(int score, int maxScore) {
  if (score <= 0 || maxScore <= 0) return null;
  final p = score / maxScore;
  if (p < 0.4) return NlaGstBand.score0to15;
  if (p < 0.7) return NlaGstBand.score16to27;
  return NlaGstBand.score28to40;
}

/// Counts by sex. Learners whose sex is neither M nor F count in the total only.
class NlaCounts {
  int male = 0;
  int female = 0;
  int other = 0;

  int get total => male + female + other;

  void add(String? sex) {
    switch ((sex ?? '').trim().toUpperCase()) {
      case 'M' || 'MALE':
        male++;
      case 'F' || 'FEMALE':
        female++;
      default:
        other++;
    }
  }

  void addAll(NlaCounts o) {
    male += o.male;
    female += o.female;
    other += o.other;
  }

  static NlaCounts sum(Iterable<NlaCounts> all) {
    final s = NlaCounts();
    for (final c in all) {
      s.addAll(c);
    }
    return s;
  }
}
