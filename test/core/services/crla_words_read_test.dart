// CRLA Part 2 words read follows the CRLA2 scoresheet (command pass F10):
// story words - miscues; a typed value only when no story matches.
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('with a story: story words minus miscues', () {
    expect(crlaWordsRead(storyWords: 96, miscues: 2), 94);
    expect(crlaWordsRead(storyWords: 96, miscues: 0), 96);
    expect(crlaWordsRead(storyWords: 96, miscues: 96), 0);
    // English stories are 100 words: the ENG sheet's 100 - miscues.
    expect(crlaWordsRead(storyWords: 100, miscues: 7), 93);
  });

  test('with a story: more miscues than words is refused', () {
    expect(() => crlaWordsRead(storyWords: 96, miscues: 97),
        throwsA(isA<CrlaWordsReadException>().having((e) => e.message, 'message', contains('97 miscues'))));
  });

  test('with a story: a typed value must agree with the story (a scoresheet row does)', () {
    expect(crlaWordsRead(storyWords: 96, miscues: 2, typed: 94), 94);
    expect(() => crlaWordsRead(storyWords: 96, miscues: 2, typed: 90),
        throwsA(isA<CrlaWordsReadException>().having((e) => e.message, 'message', contains('96 - 2 = 94'))));
  });

  test('no story: the typed value, which is required', () {
    expect(crlaWordsRead(storyWords: null, miscues: 2, typed: 40), 40);
    expect(() => crlaWordsRead(storyWords: null, miscues: 2),
        throwsA(isA<CrlaWordsReadException>().having((e) => e.message, 'message', contains('words='))));
    expect(() => crlaWordsRead(storyWords: null, miscues: 2, typed: -1), throwsA(isA<CrlaWordsReadException>()));
  });
}
