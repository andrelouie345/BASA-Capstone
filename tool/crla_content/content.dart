// Digitized CRLA content (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md
// D1-D2): the JSON the 19 Region X forms are typed into
// (supabase/seeds/crla_content/region10.json), its checks against the printed
// forms and the stored stories, and the SQL seed built from it. Format: README.md.
import 'package:basa_capstone/core/models/crla_marks.dart' show CrlaTask;
import 'package:basa_capstone/core/services/crla_digitized.dart' show crlaStoryWords;
import 'package:basa_capstone/core/services/crla_rules.dart' show crlaComprehensionMax;

class CrlaContentItem {
  final String text;
  final int? sentenceNo;
  /// The printed correct response, for an item the tutor checks against a key
  /// (Grade 1 rhyming word pairs: "Rhyme" / "No"); null for items read aloud.
  final String? answer;
  const CrlaContentItem(this.text, this.sentenceNo, [this.answer]);
}

class CrlaContentTask {
  final CrlaTask task;
  final int max;
  final List<CrlaContentItem> items;
  /// The form prints more items than it scores (e.g. two sentences of 11 words
  /// scored out of 10): the score is capped at [max].
  final bool formMiscount;
  const CrlaContentTask(this.task, this.max, this.items, [this.formMiscount = false]);
}

class CrlaContentQuestion {
  final int afterSentence;
  final String question, acceptedAnswers;
  const CrlaContentQuestion(this.afterSentence, this.question, this.acceptedAnswers);
}

class CrlaContentStory {
  final int storyNo;
  final String title;
  final int wordCount;
  /// Each printed row of the record form: its text, its printed word count,
  /// and whether the form miscounts it (the printed count stays the official
  /// one: the story's word count and scoring are built from it).
  final List<({String text, int words, bool formMiscount})> sentences;
  final List<CrlaContentQuestion> questions;
  /// The form's printed total ([wordCount], as BASA stores it) differs from
  /// its rows' sum: the stored total stays (scoring uses it).
  final bool formTotalDiffers;
  const CrlaContentStory(this.storyNo, this.title, this.wordCount, this.sentences, this.questions,
      [this.formTotalDiffers = false]);

  String get body => [for (final s in sentences) s.text.trim()].join('\n');
}

class CrlaContentForm {
  final String language;
  final int grade;
  /// `mt`, `fil` or `eng`: decides the Part 1 tasks and the number of questions.
  final String variant;
  final List<CrlaContentTask> tasks;
  final List<CrlaContentStory> stories;
  const CrlaContentForm(this.language, this.grade, this.variant, this.tasks, this.stories);

  String get name => '$language Grade $grade';
}

class CrlaContent {
  final int regionId;
  final List<CrlaContentForm> forms;
  const CrlaContent(this.regionId, this.forms);

  factory CrlaContent.fromJson(Map<String, Object?> j) => CrlaContent(
        (j['region_id'] as num).toInt(),
        [
          for (final f in (j['forms'] as List).cast<Map<String, Object?>>())
            CrlaContentForm(
              f['language'] as String,
              (f['grade'] as num).toInt(),
              f['variant'] as String,
              [
                for (final MapEntry(key: name, value: t) in (f['tasks'] as Map<String, Object?>).entries)
                  CrlaContentTask(
                    CrlaTask.fromString(name),
                    ((t as Map<String, Object?>)['max'] as num).toInt(),
                    [
                      for (final i in (t['items'] as List).cast<Map<String, Object?>>())
                        CrlaContentItem(i['text'] as String, (i['sentence_no'] as num?)?.toInt(), i['answer'] as String?),
                    ],
                    t['form_miscount'] == true,
                  ),
              ],
              [
                for (final s in (f['stories'] as List).cast<Map<String, Object?>>())
                  CrlaContentStory(
                    (s['story_no'] as num).toInt(),
                    s['title'] as String,
                    (s['word_count'] as num).toInt(),
                    [
                      for (final l in (s['sentences'] as List).cast<Map<String, Object?>>())
                        (
                          text: l['text'] as String,
                          words: (l['words'] as num).toInt(),
                          formMiscount: l['form_miscount'] == true,
                        ),
                    ],
                    [
                      for (final q in (s['questions'] as List).cast<Map<String, Object?>>())
                        CrlaContentQuestion((q['after_sentence'] as num).toInt(), q['question'] as String,
                            q['accepted_answers'] as String),
                    ],
                    s['form_total_differs'] == true,
                  ),
              ],
            ),
        ],
      );
}

/// The stories BASA stores (crla_stories of the region): (language, grade,
/// story_no) -> title and word count.
typedef CrlaStoredStories = Map<(String, int, int), ({String title, int wordCount})>;

const _standardTasks = {CrlaTask.task1, CrlaTask.task2Low, CrlaTask.task2High};
const _englishTasks = {CrlaTask.task1, CrlaTask.task2};

/// Everything in [c] that doesn't match the printed forms or [stored]; empty =
/// OK. One line per problem, naming the form.
List<String> checkCrlaContent(CrlaContent c, CrlaStoredStories stored) {
  final problems = <String>[];
  for (final f in c.forms) {
    void problem(String s) => problems.add('${f.name}: $s');
    final wanted = f.variant == 'eng' ? _englishTasks : _standardTasks;
    final have = {for (final t in f.tasks) t.task};
    if (!have.containsAll(wanted) || have.length != wanted.length) {
      problem('tasks are ${have.map((t) => t.value).join(', ')}, expected ${wanted.map((t) => t.value).join(', ')}');
    }
    for (final t in f.tasks) {
      if (t.items.length != t.max && !(t.formMiscount && t.items.length > t.max)) {
        problem('${t.task.value} has ${t.items.length} items, the form has ${t.max}');
      }
      if (t.items.any((i) => i.text.trim().isEmpty)) problem('${t.task.value} has an empty item');
    }
    for (final s in f.stories) {
      final key = (f.language, f.grade, s.storyNo);
      final db = stored[key];
      if (db == null) {
        problem('story ${s.storyNo}: no stored story for this language and grade');
      } else {
        if (db.title != s.title) problem('story ${s.storyNo}: title "${s.title}", stored "${db.title}"');
        if (db.wordCount != s.wordCount) {
          problem('story ${s.storyNo}: word count ${s.wordCount} in the file, stored ${db.wordCount}');
        }
      }
      for (final (i, line) in s.sentences.indexed) {
        final n = crlaStoryWords(line.text).length;
        if (n != line.words && !line.formMiscount) {
          problem('story ${s.storyNo}, sentence ${i + 1}: $n words, the form prints ${line.words}');
        }
      }
      final printed = s.sentences.fold<int>(0, (a, l) => a + l.words);
      if (printed != s.wordCount && !s.formTotalDiffers) {
        problem('story ${s.storyNo}: the printed counts add up to $printed, its word count is ${s.wordCount}');
      }
      final max = crlaComprehensionMax(f.grade, f.variant);
      if (s.questions.length != max) problem('story ${s.storyNo}: ${s.questions.length} questions, the grade has $max');
      for (final q in s.questions) {
        if (q.afterSentence < 1 || q.afterSentence > s.sentences.length) {
          problem('story ${s.storyNo}: a question follows sentence ${q.afterSentence}, which is not in the story');
        }
      }
    }
    for (final MapEntry(key: (language, grade, storyNo)) in stored.entries) {
      if (language == f.language && grade == f.grade && !f.stories.any((s) => s.storyNo == storyNo)) {
        problem('stored story $storyNo has no text in the file');
      }
    }
  }
  return problems;
}

/// The rows the forms miscount (marked `form_miscount`), for the owner's
/// spot-check list.
List<String> crlaContentNotes(CrlaContent c) => [
      for (final f in c.forms)
        for (final t in f.tasks)
          if (t.formMiscount) '${f.name}: ${t.task.value} has ${t.items.length} items, scored out of ${t.max}',
      for (final f in c.forms)
        for (final s in f.stories)
          if (s.formTotalDiffers)
            '${f.name}: story ${s.storyNo}: its rows add up to ${s.sentences.fold<int>(0, (a, l) => a + l.words)}, '
                'the form prints ${s.wordCount} (kept)',
      for (final f in c.forms)
        for (final s in f.stories)
          for (final (i, line) in s.sentences.indexed)
            if (line.formMiscount)
              '${f.name}: story ${s.storyNo}, sentence ${i + 1}: ${crlaStoryWords(line.text).length} words, '
                  'the form prints ${line.words} ("${line.text}")',
    ];

String _q(String s) => "'${s.replaceAll("'", "''")}'";

/// The idempotent seed: each story's text, the Part 1 items and the
/// questions (upserts; run after migration 20261127010000).
String crlaContentSeed(CrlaContent c) {
  final b = StringBuffer()
    ..writeln('-- Digitized CRLA content, region ${c.regionId}: generated by tool/crla_content/build_seed.dart')
    ..writeln('-- from supabase/seeds/crla_content/region10.json. Idempotent. Run after 20261127010000.')
    ..writeln('begin;');
  for (final f in c.forms) {
    final where = 'region_id = ${c.regionId} and language = ${_q(f.language)} and grade = ${f.grade}';
    b.writeln('-- ${f.name}');
    for (final t in f.tasks) {
      for (final (i, item) in t.items.indexed) {
        b.writeln('insert into public.crla_part1_items (region_id, language, grade, task, item_no, text, sentence_no, answer_key) '
            'values (${c.regionId}, ${_q(f.language)}, ${f.grade}, ${_q(t.task.value)}, ${i + 1}, ${_q(item.text)}, '
            '${item.sentenceNo ?? 'null'}, ${item.answer == null ? 'null' : _q(item.answer!)}) '
            'on conflict (region_id, language, grade, task, item_no) do update '
            'set text = excluded.text, sentence_no = excluded.sentence_no, answer_key = excluded.answer_key;');
      }
    }
    for (final s in f.stories) {
      b.writeln('update public.crla_stories set body = ${_q(s.body)} where $where and story_no = ${s.storyNo};');
      for (final (i, q) in s.questions.indexed) {
        b.writeln('insert into public.crla_story_questions (story_id, question_no, after_sentence, question, accepted_answers) '
            'select id, ${i + 1}, ${q.afterSentence}, ${_q(q.question)}, ${_q(q.acceptedAnswers)} '
            'from public.crla_stories where $where and story_no = ${s.storyNo} '
            'on conflict (story_id, question_no) do update set after_sentence = excluded.after_sentence, '
            'question = excluded.question, accepted_answers = excluded.accepted_answers;');
      }
    }
  }
  b.writeln('commit;');
  return b.toString();
}
