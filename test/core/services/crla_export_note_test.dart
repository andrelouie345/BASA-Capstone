// CRLA2 export warns when the sheet can't show BASA's words read (F10, owner
// 2026-10-23: no round trip for those rows, a warning instead).
import 'package:basa_capstone/core/services/crla_scoresheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no note when the sheet computes the same words read', () {
    expect(crlaWordsReadExportNote('ZZTESTA, Learner001', 'fil', sheetStoryWords: 96, miscues: 2, wordsRead: 94), isNull);
    expect(crlaWordsReadExportNote('A', 'eng', sheetStoryWords: 100, miscues: 7, wordsRead: 93), isNull);
  });

  test('a note when the sheet has no story for the row', () {
    expect(crlaWordsReadExportNote('ZZTESTC, Learner003', 'mt', sheetStoryWords: null, miscues: 2, wordsRead: 40),
        "ZZTESTC, Learner003 (MT): the sheet can't show BASA's 40 words read (no matching story, or a value from "
        'before the story rule); type 40 in the sheet before importing it again.');
  });

  test('a note when an older typed value differs from the sheet formula', () {
    expect(crlaWordsReadExportNote('B', 'fil', sheetStoryWords: 96, miscues: 2, wordsRead: 90), contains('type 90'));
  });
}
