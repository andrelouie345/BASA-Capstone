// The CRLA variants and their default languages a start screen offers
// (screen inventory CRLA-G1).
import 'package:basa_capstone/core/models/crla_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the three variants', () => expect(crlaSubjectVariants, ['mt', 'fil', 'eng']));
  test('fil defaults to Tagalog', () => expect(crlaDefaultLanguage('fil'), 'Tagalog'));
  test('eng defaults to English', () => expect(crlaDefaultLanguage('eng'), 'English'));
  test('mt has no default', () => expect(crlaDefaultLanguage('mt'), isNull));
}
