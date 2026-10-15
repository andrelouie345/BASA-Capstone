// lib/core/services/aral_rules.dart
//
// Who BASA proposes for ARAL-Reading, and in which program. Pure functions;
// the coordinator confirms or changes every proposal (owner, 2026-10-15).
//
// Sources: DepEd ARAL-Reading SY 2025-2026 (orientation decks, "Check-in with
// the Regions") and the VNHS week-1 instructions/FAQ (adapted from DM 64 s2025):
//  * Grade 1: CRLA MOSY result; Grades 2-3: CRLA BOSY result. Low and High
//    Emerging readers qualify; Developing and Transitioning only when the
//    school extends the program (includeOptional).
//  * Grades 4-10: Phil-IRI (English) BOSY result. Frustration (and Non-Reader)
//    qualify; Instructional only when the school extends the program.
//  * Program: Grades 1-3 -> KS1. Phil-IRI: a Non-Reader -> KS1 (any grade);
//    otherwise the key stage follows the READING level (the adjusted level),
//    not the grade: <= 3 -> KS1, 4-6 -> KS2, 7+ -> KS3. In KS2/KS3, word
//    reading at Frustration (a decoding problem) -> Basic, otherwise (decodes,
//    weak comprehension/fluency) -> Plus.
library;

import '../models/aral_enrollment.dart';
import '../models/crla_assessment.dart' show CrlaRound;
import 'crla_rules.dart';
import 'phil_iri_rules.dart';

/// The CRLA round a Grade 1-3 learner's ARAL placement comes from.
CrlaRound aralCrlaBasisRound(int grade) => grade == 1 ? CrlaRound.mosy : CrlaRound.bosy;

/// CRLA reading profiles from weakest to strongest (for choosing between
/// variants and for the qualification rule).
const aralCrlaProfileOrder = [
  crlaLowEmerging,
  crlaHighEmerging,
  crlaDeveloping,
  crlaTransitioning,
  crlaAtGradeLevel,
];

/// The weaker of two CRLA profiles (a learner assessed in two variants is
/// placed on the one that shows more need). Unknown profiles lose.
String? aralWeakerCrlaProfile(String? a, String? b) {
  int rank(String? p) {
    if (p == null) return 99;
    return aralCrlaProfileOrder.contains(p) ? aralCrlaProfileOrder.indexOf(p) : 98;
  }
  return rank(a) <= rank(b) ? a : b;
}

bool aralCrlaQualifies(String profile, {bool includeOptional = false}) =>
    profile == crlaLowEmerging ||
    profile == crlaHighEmerging ||
    (includeOptional && (profile == crlaDeveloping || profile == crlaTransitioning));

bool aralPhilIriQualifies(PhilIriLevel profile, {bool includeOptional = false}) =>
    profile == PhilIriLevel.frustration ||
    profile == PhilIriLevel.nonReader ||
    (includeOptional && profile == PhilIriLevel.instructional);

/// Key stage from a reading level (grade 1-12): <= 3 KS1, 4-6 KS2, 7+ KS3.
AralKeyStage aralKeyStageForLevel(int level) =>
    level <= 3 ? AralKeyStage.ks1 : (level <= 6 ? AralKeyStage.ks2 : AralKeyStage.ks3);

class AralPlacement {
  final AralKeyStage keyStage;
  final AralTrack? track; // null for KS1
  const AralPlacement(this.keyStage, [this.track]);

  String get label => track == null ? keyStage.label : '${keyStage.label} ${track!.label}';

  @override
  bool operator ==(Object other) => other is AralPlacement && other.keyStage == keyStage && other.track == track;
  @override
  int get hashCode => Object.hash(keyStage, track);
}

/// Grades 1-3 (CRLA) are always KS1.
const aralCrlaPlacement = AralPlacement(AralKeyStage.ks1);

/// The program for a Phil-IRI result. [adjustedLevel] is the learner's reading
/// level (philIriAdjustedLevel); when it is unknown the learner's grade is used.
AralPlacement aralPhilIriPlacement({
  required PhilIriLevel profile,
  required PhilIriLevel? wordReadingLevel,
  required int? adjustedLevel,
  required int grade,
}) {
  if (profile == PhilIriLevel.nonReader || wordReadingLevel == PhilIriLevel.nonReader) {
    return const AralPlacement(AralKeyStage.ks1);
  }
  final ks = aralKeyStageForLevel(adjustedLevel != null && adjustedLevel > 0 ? adjustedLevel : grade);
  if (ks == AralKeyStage.ks1) return const AralPlacement(AralKeyStage.ks1);
  final decoding = wordReadingLevel == PhilIriLevel.frustration;
  return AralPlacement(ks, decoding ? AralTrack.basic : AralTrack.plus);
}
