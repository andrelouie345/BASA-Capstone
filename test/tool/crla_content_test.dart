// The CRLA content checker and seed builder (digitized CRLA plan Task 2, spec
// D1-D2): a made-up two-form fixture, not real DepEd content.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/crla_content/content.dart';

Map<String, Object?> _form({
  String language = 'English',
  int grade = 3,
  String variant = 'eng',
  int task1Items = 10,
  int questions = 6,
  String firstLine = 'One two three four five.',
  int firstLineWords = 5,
  int storyWords = 10,
  String title = 'Story One',
}) =>
    {
      'language': language,
      'grade': grade,
      'variant': variant,
      'tasks': {
        'task1': {
          'max': 10,
          'items': [for (var i = 0; i < task1Items; i++) {'text': 'w$i'}],
        },
        'task2': {
          'max': 10,
          'items': [
            for (var i = 0; i < 10; i++) {'text': 's$i', 'sentence_no': i < 5 ? 1 : 2},
          ],
        },
      },
      'stories': [
        {
          'story_no': 1,
          'title': title,
          'word_count': storyWords,
          'sentences': [
            {'text': firstLine, 'words': firstLineWords},
            {'text': 'Six seven eight nine ten.', 'words': 5},
          ],
          'questions': [
            for (var q = 1; q <= questions; q++)
              {'after_sentence': 2, 'question': 'Question $q?', 'accepted_answers': 'Any of these - a, b'},
          ],
        },
      ],
    };

void main() {
  final stored = {('English', 3, 1): (title: 'Story One', wordCount: 10)};
  List<String> check(Map<String, Object?> form) =>
      checkCrlaContent(CrlaContent.fromJson({'region_id': 13, 'forms': [form]}), stored);

  test('a correct form has no problems', () {
    expect(check(_form()), isEmpty);
  });

  test("a sentence whose words differ from its printed count is a problem", () {
    expect(check(_form(firstLineWords: 4)), anyElement(contains('sentence 1')));
  });

  test('a row marked as a form miscount is a note, not a problem, and the total follows the printed counts', () {
    final f = _form(firstLine: 'One two three four five six.', firstLineWords: 5);
    expect(check(f).single, contains('sentence 1'));
    (((f['stories'] as List).first as Map)['sentences'] as List).first['form_miscount'] = true;
    expect(check(f), isEmpty);
    expect(crlaContentNotes(CrlaContent.fromJson({'region_id': 13, 'forms': [f]})).single,
        contains('6 words, the form prints 5'));
  });

  test('a story whose rows add up to more than its printed total, when flagged, is a note', () {
    final f = _form(firstLine: 'One two three four five six.', firstLineWords: 6);
    expect(check(f).single, contains('add up to 11'));
    ((f['stories'] as List).first as Map)['form_total_differs'] = true;
    expect(check(f), isEmpty);
    expect(crlaContentNotes(CrlaContent.fromJson({'region_id': 13, 'forms': [f]})).single,
        contains('rows add up to 11, the form prints 10'));
  });

  test('a story total differing from crla_stories.word_count is a problem', () {
    expect(check(_form(storyWords: 11)), anyElement(contains('word count')));
  });

  test("a task with other than its printed maximum of items is a problem", () {
    expect(check(_form(task1Items: 9)).single, contains('task1'));
  });

  test('a task marked as a form miscount (11 words scored out of 10) is a note', () {
    final f = _form(task1Items: 11);
    expect(check(f).single, contains('task1'));
    ((f['tasks'] as Map)['task1'] as Map)['form_miscount'] = true;
    expect(check(f), isEmpty);
    expect(crlaContentNotes(CrlaContent.fromJson({'region_id': 13, 'forms': [f]})).single,
        contains('task1 has 11 items, scored out of 10'));
  });

  test('a story with other than the grade\'s number of questions is a problem', () {
    expect(check(_form(questions: 5)).single, contains('questions'));
  });

  test('a title differing from crla_stories is a problem', () {
    expect(check(_form(title: 'Story 1')).single, contains('title'));
  });

  test('a form with no stored story is a problem', () {
    expect(check(_form(language: 'Ilokano')), anyElement(contains('no stored story')));
  });

  test('the seed is idempotent SQL', () {
    final sql = crlaContentSeed(CrlaContent.fromJson({'region_id': 13, 'forms': [_form()]}));
    expect(sql, contains("update public.crla_stories set body = 'One two three four five.\nSix seven eight nine ten.'"));
    expect(sql, contains("where region_id = 13 and language = 'English' and grade = 3 and story_no = 1"));
    expect(sql, contains('on conflict (region_id, language, grade, task, item_no) do update'));
    expect(sql, contains('on conflict (story_id, question_no) do update'));
    expect(sql, contains("'Question 1?'"));
  });

  test('an item with an answer key (rhyming pairs) carries it into the seed', () {
    final f = _form();
    ((f['tasks'] as Map)['task1'] as Map)['items'] = [
      {'text': 'bulsa, tasa', 'answer': 'Rhyme'},
      for (var i = 1; i < 10; i++) {'text': 'w$i'},
    ];
    final sql = crlaContentSeed(CrlaContent.fromJson({'region_id': 13, 'forms': [f]}));
    expect(sql, contains("'bulsa, tasa', null, 'Rhyme')"));
    expect(sql, contains("'w1', null, null)"));
  });

  test("quotes are doubled in the SQL", () {
    final f = _form(firstLine: "Iba't two three four five.");
    expect(crlaContentSeed(CrlaContent.fromJson({'region_id': 13, 'forms': [f]})), contains("Iba''t two"));
  });
}
