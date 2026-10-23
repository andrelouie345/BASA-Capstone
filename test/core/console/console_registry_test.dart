// A command name registered twice (for example in both the tutor and the
// admin half of a split command file) must fail loudly, not overwrite.
import 'package:basa_capstone/core/console/console_command.dart';
import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleCommand _cmd(String name, String result) =>
    ConsoleCommand(name: name, description: name, handler: (_) async => result);

void main() {
  test('registering the same name twice throws', () {
    final r = ConsoleRegistry()..register(_cmd('whoami', 'first'));

    expect(() => r.register(_cmd('whoami', 'second')), throwsStateError);
  });

  test('the first registration is kept after a refused duplicate', () async {
    final r = ConsoleRegistry()..register(_cmd('whoami', 'first'));
    try {
      r.register(_cmd('whoami', 'second'));
    } on StateError {
      // expected
    }

    expect(await r.execute('whoami'), 'first');
  });
}
