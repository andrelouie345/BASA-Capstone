// A check-in score as a screen shows it: met at the cut-off, whole percent
// (spec docs/superpowers/specs/2026-10-24-vm-completeness-design.md, ARAL-G2).
import 'package:basa_capstone/core/models/aral_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes at the cut-off', () {
    expect(const AralCheckinScore(15, 20, 20).passes(75), isTrue); // 1500 == 75 * 20
    expect(const AralCheckinScore(14, 20, 20).passes(75), isFalse);
    expect(const AralCheckinScore(0, 0, 0).passes(1), isFalse);
  });

  test('wholePercent of 2/3 is 67', () {
    expect(const AralCheckinScore(2, 3, 3).wholePercent, 67);
  });

  test('wholePercent of 1/8 is 13', () {
    const s = AralCheckinScore(1, 8, 8);
    expect(s.wholePercent, 13);
    expect('${s.wholePercent}', s.percent.toStringAsFixed(0));
  });

  test('wholePercent of no items is 0', () {
    expect(const AralCheckinScore(0, 0, 0).wholePercent, 0);
  });
}
