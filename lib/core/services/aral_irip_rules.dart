// lib/core/services/aral_irip_rules.dart
//
// IRIP target suggestions (pure). From the IRIP status legend: Observed ->
// ready to proceed to the next reading target; Partially observed -> more
// practice on the current target; Not observed -> reteach the current target.
// Owner decision (2026-10-16): BASA suggests, the tutor may pick another
// target from the list.
library;

import '../models/aral_irip.dart';

/// Weeks in one IRIP cycle.
const aralIripWeeks = 8;

/// The suggested target after [current] was rated [status], from [strandList]
/// (the strand's active targets in order). Null when [current] was the last
/// target and it was observed: the strand's list is done and the tutor picks
/// a target to review.
AralIripTarget? aralIripSuggest(List<AralIripTarget> strandList, AralIripTarget current, AralIripStatus status) {
  if (status != AralIripStatus.observed) return current;
  final later = strandList.where((t) => t.seq > current.seq).toList()..sort((a, b) => a.seq.compareTo(b.seq));
  return later.isEmpty ? null : later.first;
}

/// The first target of a strand's list (week 1 is pre-assigned).
AralIripTarget? aralIripFirst(List<AralIripTarget> strandList) {
  if (strandList.isEmpty) return null;
  return strandList.reduce((a, b) => a.seq <= b.seq ? a : b);
}
