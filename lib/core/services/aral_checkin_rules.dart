// lib/core/services/aral_checkin_rules.dart
//
// Check-in scoring (owner decisions 2026-10-16): one point per item; an item
// with no answer counts as wrong; a score passes when it is at least the
// cut-off percentage of the items, overall and per part. The cut-off is
// adjustable (aral_settings: defaults <- region <- school) and judged when
// read, so changing it re-judges old check-ins.
import '../models/aral_checkin.dart';

/// The checkpoints a tool is given after.
const aralCheckinCheckpoints = [16, 32];

/// The adjustable check-in settings (keys of aral_settings.settings).
class AralCheckinSettings {
  static const passPctKey = 'checkin_pass_pct';
  static const defaults = AralCheckinSettings(passPct: 75);

  final int passPct; // 1-100

  const AralCheckinSettings({required this.passPct});

  /// Defaults, then [m]'s keys (unknown keys and bad values are ignored).
  factory AralCheckinSettings.fromMap(Map<String, Object?> m) {
    final v = m[passPctKey];
    return AralCheckinSettings(passPct: v is num && v >= 1 && v <= 100 ? v.round() : defaults.passPct);
  }

  Map<String, Object?> toMap() => {passPctKey: passPct};
}

/// A score out of [total] items.
class AralCheckinScore {
  final int correct;
  final int answered;
  final int total;

  const AralCheckinScore(this.correct, this.answered, this.total);

  double get percent => total == 0 ? 0 : correct * 100 / total;

  /// [percent] rounded to a whole number, as screens and the console show it.
  int get wholePercent => percent.round();

  /// At least [passPct] percent of the items (compared in whole numbers).
  bool passes(int passPct) => total > 0 && correct * 100 >= passPct * total;

  @override
  String toString() => '$correct/$total';
}

/// The score of one check-in: overall and per part (in the sheet's order;
/// empty when the tool has no parts).
class AralCheckinScoring {
  final AralCheckinScore overall;
  final Map<String, AralCheckinScore> sections;
  const AralCheckinScoring(this.overall, this.sections);

  bool get complete => overall.answered == overall.total;
}

AralCheckinScoring aralCheckinScore(List<AralCheckinItem> items, List<AralCheckinAnswer> answers) {
  final byItem = {for (final a in answers) a.itemId: a};
  AralCheckinScore score(Iterable<AralCheckinItem> list) {
    var correct = 0, answered = 0, total = 0;
    for (final i in list) {
      total++;
      final a = byItem[i.id];
      if (a == null) continue;
      answered++;
      if (a.isCorrect) correct++;
    }
    return AralCheckinScore(correct, answered, total);
  }

  final sorted = [...items]..sort((a, b) => a.itemNo.compareTo(b.itemNo));
  final sections = <String, AralCheckinScore>{};
  for (final name in sorted.map((i) => i.section).whereType<String>().toSet()) {
    sections[name] = score(sorted.where((i) => i.section == name));
  }
  return AralCheckinScoring(score(sorted), sections);
}
