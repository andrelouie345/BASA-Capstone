// The demo builder's upload packages (demo-data plan Task 6).
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/sync_steps.dart';

void main() {
  test('items are grouped so each package stays under the limit', () {
    expect(packages([40, 40, 40, 90], (b) => b, 100), [
      [40, 40],
      [40],
      [90],
    ]);
  });

  test('an item over the limit alone is refused', () {
    expect(() => packages([40, 120], (b) => b, 100), throwsStateError);
  });

  test('no items, no packages', () {
    expect(packages(<int>[], (b) => b, 100), isEmpty);
  });
}
